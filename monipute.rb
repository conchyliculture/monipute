require "openssl"
require "tempfile"
require "timeout"

class PuteError < StandardError
  # Always nice to have your own Error
end

module Pute
  class Pute
    attr_accessor :timeout

    # Basic class, sets defaults and does nothing.
    def check()
      # example:
      # alert("OMG!")
    end

    def alert(msg = nil)
      raise PuteError, msg || "#{self.class} has failed!"
    end
  end

  class Web < Pute
    # Checks that url answers with an http code (string) and contains a string in its body
    require "uri"
    require "net/http"
    def initialize(url, expected_string: nil, code: "200", timeout: 5, extra_headers: {})
      super()
      @url = url
      @code = code
      @expected_string = expected_string
      @timeout = timeout
      @extra_headers = extra_headers
    end

    def get_stuff
      return Net::HTTP.get_response(URI(@url))
    end

    def check
      error_messages = []
      begin
        pute = get_stuff()
        unless pute.code == @code
          error_messages << "got code #{pute.code}, expected #{@code}"
        end
        if @expected_string and pute.body.force_encoding('utf-8') !~ /#{@expected_string}/
          error_messages << "couldn't find expected string #{@expected_string}"
        end
        if @extra_headers != {}
          @extra_headers.each do |k, v|
            h = pute.to_hash
            if not h[k]
              error_messages << "expected HTTP response header #{k} not found in #{h}"
            elsif h[k] != v
              error_messages << "expected HTTP response header value for #{k} is '#{v}' but got #{h[k]}"
            end
          end
        end
      rescue StandardError => e
        alert("Error fetching #{@url}: #{e.class} #{e.message}")
      end

      unless error_messages.empty?
        alert("Error fetching #{@url}: \n\t#{error_messages.join("\n\t")}")
      end
    end

    def to_s
      return @url
    end
  end

  class Websus < Web
    # For when you don't want to check the SSL certificate
    def get_stuff()
      uri = URI(@url)
      response = nil
      Net::HTTP.start(uri.host, uri.port, use_ssl: (uri.port == 443), verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
        request = Net::HTTP::Get.new uri
        response = http.request request
      end
      return response
    end
  end

  class Process < Pute
    # Checks at least one process exists by name, using pgrep
    def initialize(processname)
      super()
      @processname = processname
    end

    def check()
      pids = IO.popen("pgrep \"#{@processname}\"").read().split
      if pids.empty?
        alert("No process called #{@processname}")
      end
    end
  end

  class LoadAverage < Pute
    require "vmstat"
    def initialize(max_load = 90)
      super()
      @max_load = max_load
    end

    def check()
      l = Vmstat.snapshot.load_average.one_minute
      alert("Load too high: #{l} > #{@max_load}") if l > @max_load
    end
  end
end

def send_email(content, destination, subject)
  file = Tempfile.new('monipute')
  file.write(content)
  file.close
  puts "sending email to #{destination} with file #{file.path}"

  `mail -s "#{subject.strip}" "#{destination}" < "#{file.path}"`

  file.unlink
end

def send_emails(content, destination, subject: "Monitoring is sad")
  if destination.instance_of?(String)
    send_email(content, destination, subject)
  elsif destination.instance_of?(Array)
    destination.each do |d|
      send_email(content, d, subject)
    end
  end
end

def error(msg)
  puts msg # This is fine if running from Cron, because cron will send a mail
  # send_emails(msg, "admin@example.com")
end

res = ""
# Here goes your tests
[
  Pute::LoadAverage.new(0),
  Pute::Process.new("bash"),
  Pute::Web.new("http://google.fr/", expected_string: "<body", code: "301"),
  Pute::Web.new("https://twitter.com/")
].each do |s|
  Timeout.timeout(s.timeout) { s.check }
rescue Timeout::Error
  res << "We waited too long on #{s}" << "\n\n"
rescue PuteError => e
  res << e.to_s << "\n\n"
rescue StandardError => e
  res << "We crashed doing #{s.class}:\n#{e.message}\n\n"
end

error(res) if res != ""
