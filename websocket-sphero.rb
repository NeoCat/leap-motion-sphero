#!/usr/bin/ruby

require 'em-websocket'
require 'sphero'

Sphero.start "/dev/tty.Sphero-RWP-AMP-SPP" do |s|
  puts "Connected to Sphero!"
  sleep 1
  3.times do
    begin
      s.color 'green'
    rescue
    end
  end
  keep_going 1
  s.color 'black'
  calibration = 0

  EM.run {
    EM::WebSocket.run(:host => "0.0.0.0", :port => 8080) do |ws|

      mutex_sphero = Mutex.new  # to allow only 1 thread to talk with sphero
      mutex_req = Mutex.new     # to protect req
      req = nil

      ws.onopen { |handshake|
        puts "WebSocket connection open"
      }

      ws.onclose { puts "Connection closed" }

      ws.onmessage { |msg|
        puts "Recieved message: #{msg}"

        if msg == 'start'
          mutex_sphero.synchronize { s.color 'blue', true }

        elsif msg == 'stop'
          mutex_sphero.synchronize {
            s.color 'black', true
            stop
            mutex_req.synchronize { req = nil }
          }

        elsif msg == 'calibrate+' or msg == 'calibrate-'
          mutex_sphero.synchronize {
            s.color 'black'
            s.back_led_output = 0xff
            calibration = (calibration + (msg == "calibrate+" ? 15 : 360-15)) % 360
            puts "calibration = #{calibration}"
            s.roll 0, calibration
          }
          EM.cancel_timer(@calib_timer) if @calib_timer
          @calib_timer = EM.add_timer(3) do
            mutex_sphero.synchronize { s.back_led_output = 0 }
          end

        else
          data = msg.split(',').map {|d| d.to_i }
          speed = [Math.sqrt(data[0]**2 + data[1]**2)*20, 0xff].min.to_i
          deg = Math.atan2(data[0], data[1]) / Math::PI * 180
          deg = (deg + calibration + 360) % 360
          p [speed, deg.to_i]

          # Sending request to sphero may take some time;
          # Use EM.defer to send in background
          mutex_req.synchronize { req = [speed, deg.to_i] } # set a new request
          EM.defer do                       # in a new thread ...
            mutex_sphero.synchronize do
              r = nil
              mutex_req.synchronize { r, req = req, r } # get & clear req
              s.roll *r if r                # if we got the newest request, send it!
            end
          end

        end
      }
    end
  }

end
