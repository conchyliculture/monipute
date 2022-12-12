#!/usr/bin/ruby

require "openssl"
require "pp"
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
            begin
                pute = get_stuff()
                unless pute.code == @code
                    alert("Error fetching #{@url} got code #{pute.code}, expected #{@code}")
                end
                if @code == 200 and not pute.body =~ /#{@expected_string}/
                    alert("Error fetching #{@url} couldn't find expected string #{@expected_string}")
                end
                if @extra_headers != {}
                  @extra_headers.each do |k,v|
                    h = pute.to_hash
                    if not h[k]
                      alert("Error fetching #{@url}: expected HTTP response header #{k} not found in #{h}")
                    elsif h[k] != v
                      alert("Error fetching #{@url}: expected HTTP response header value for #{k} is '#{v}' but got #{h[k]}")
                    end
                  end
                end
            rescue Exception => e
                alert("#{self.class}: #{e.class} #{e.message} with #{@url}")
            end
        end
        def to_s
            return @url
        end
    end

    class Webs < Web
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


def error(msg)
    # TODO
    puts msg # This is fine if running from Cron, because cron will send a mail 
end

res=""
# Here goes your tests
[
    Pute::Process.new("bash"),
    Pute::Web.new("http://google.fr/",expected_string: "<body",code: "301"),
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
