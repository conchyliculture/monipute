#!/usr/bin/ruby

require "openssl"
require "tempfile"
require "timeout"

class PuteError < Exception
    # Always nice to have your own Error
    def initialize(msg)
        super
    end
end

module Pute
    class Pute
        attr_accessor :timeout
        # Basic class, sets defaults and does nothing.
        def check()
            # We don't care about return value yet
            # Call alert()
            if false
                alert("OMG!")
            end
        end
        def alert(msg=nil)
            raise PuteError.new(msg || "#{self.class} has failed!")
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
                if @expected_string and not pute.body.force_encoding('utf-8') =~ /#{@expected_string}/
                    error_messages << "couldn't find expected string #{@expected_string}"
                end
                if @extra_headers != {}
                  @extra_headers.each do |k,v|
                    h = pute.to_hash
                    if not h[k]
                      error_messages << "expected HTTP response header #{k} not found in #{h}"
                    elsif h[k] != v
                      error_messages << "expected HTTP response header value for #{k} is '#{v}' but got #{h[k]}"
                    end
                  end
                end
            rescue Exception => e
                alert("Error fetching #{@url}: #{e.class} #{e.message}")
            end

            if not error_messages.empty?
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
            Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.port == 443), :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|
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
            @processname=processname
        end

        def check()
            pids = IO.popen("pgrep \"#{@processname}\"").read().split
            unless pids.size > 0
                alert("No process called #{@processname}")
            end
        end
    end
end

def send_email(content, destination, subject: "Monitoring is sad")
  file = Tempfile.new('monipute')
  file.write(content)
  file.close
  puts "sending email to #{destination} with file #{file.path}"

  `mail -s "#{subject.strip}" "#{destination}" < "#{file.path}"`

  file.unlink
end

def send_emails(content, destination, subject: "Monitoring is sad")
  if destination.class == String
    send_email(content, destination)
  elsif destination.class == Array
    destination.each do |d|
      send_email(content, d)
    end
  end
end


def error(msg)
    # TODO
    puts msg # This is fine if running from Cron, because cron will send a mail 
#    send_emails(msg, "admin@example.com")
end

res=""
# Here goes your tests
[
    Pute::Process.new("bash"),
    Pute::Web.new("http://google.fr/", expected_string: "<body", code: "301"),
    Pute::Web.new("https://twitter.com/"),
].each do |s|
    begin
        Timeout::timeout(s.timeout) { s.check }
    rescue Timeout::Error => e
        res << "We waited too long on #{s.to_s}" << "\n\n"
    rescue PuteError => e
        res << "#{e.message}" << "\n\n"
    rescue Exception => e
        res << "We crashed doing #{s.class}:\n"+e.message+"\n\n"
    end
end

error(res) if res!=""
