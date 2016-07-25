#!/usr/bin/ruby
require "pp"
require "timeout"

class PuteError < Exception
    def initialise()
        super
    end
end

module Pute
    class Pute
        def timeout
            return 5
        end
        def check()
            return true
        end
        def alert(msg=nil)
            raise PuteError.new(msg || "#{self.class} has failed!")
        end
    end

    class Web < Pute
        require "uri"
        require "net/http"
        def initialize(url,expected_string="<body",code="200")
            super()
            @url=url
            @code=code
            @expected_string=expected_string
        end

        def check
            begin
                pute = Net::HTTP.get_response(URI(@url))
                unless pute.code == @code
                    alert("Error fetching #{@url} got code #{pute.code}, expected #{@code}")
                end
                if @code == 200 and not pute.body =~ /#{@expected_string}/
                    alert("Error fetching #{@url} couldn't find expected string #{@expected_string}")
                end
            rescue Exception => e
                alert("#{self.class}: #{e.class} #{e.message} with #{@url}")
            end
        end
    end

    class Process < Pute
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

def hostname()
    return File.open("/etc/mailname").read().strip()
end

$from = "monipute@"+hostname()
$from_address = "pute@pute" 

def send_mail(msg,subj="PuteWarn")
    puts msg 
end

res=""
[
    Pute::Process.new("bash"),
    Pute::Web.new("http://google.fr/",expected_string="<body",code="301"),
    Pute::Web.new("https://twitter.com/"),
].each do |s|
    begin
        Timeout::timeout(s.timeout) { s.check }
    rescue Timeout::Error => e
        res << "#{e.message}" << "\n\n"
    rescue PuteError => e
        res << "#{e.message}" << "\n\n"
    rescue Exception => e
        res << "We crashed doing #{s.class}:\n"+e.message+"\n\n"
    end
end

send_mail(res) if res!=""
