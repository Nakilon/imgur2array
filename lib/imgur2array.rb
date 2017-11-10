module Imgur
  class << self
    attr_accessor :logger
  end

  class Error < RuntimeError
    def initialize body
      Module.nesting[1].logger.error body
      super "Imgur error: #{body}"
    end
  end

  require "nethttputils"
  def self.imgur_to_array link
    case link
    when /\Ahttps?:\/\/((m|i|www)\.)?imgur\.com\/(a|gallery|r\/[A-Za-z0-9][A-Za-z0-9_]{2,20})\/[a-zA-Z0-9]{5,7}(#[a-zA-Z0-9]{7})?\z/
      fail link.inspect unless /\/(?<type>a|gallery|r\/[A-Za-z0-9][A-Za-z0-9_]{2,20})\/(?<id>[a-zA-Z0-9]{5,7})/ =~ link
      json = NetHTTPUtils.request_data "https://api.imgur.com/3/#{
        type == "gallery" ? "gallery" : "album"
      }/#{id}/0.json",
        header: { Authorization: "Client-ID #{ENV["IMGUR_CLIENT_ID"]}" }
      data_imgur = JSON.parse(json)["data"]
      if data_imgur["error"]
        fail data_imgur.inspect
        logger.error "imgur error: #{data_imgur["error"]}"; []
      elsif data_imgur["images"]
        data_imgur["images"]
      elsif data_imgur["type"] && data_imgur["type"].start_with?("image/")
        [ data_imgur ]
      # elsif data_imgur["comment"]
      #   fi["https://imgur.com/" + data_imgur["image_id"]]
      else
        fail data_imgur.inspect
      end
    when /\/\/i\./,
         /\Ahttps?:\/\/((m|www)\.)?imgur\.com\/[a-zA-Z0-9]{7}(\?r|\.jpg|\.gifv)?\z/
      json = NetHTTPUtils.request_data "https://api.imgur.com/3/image/#{
        link[/[a-zA-Z0-9]{7}/]
      }/0.json",
        header: { Authorization: "Client-ID #{ENV["IMGUR_CLIENT_ID"]}" }
      [ JSON.load(json)["data"] ]
    else
      raise Error.new "bad link pattern #{link.inspect}"
    end.map do |_|
      case _["type"]
      when "image/jpeg", "image/png", "image/gif"
        _["link"]
      else
        raise Error.new "unknown type of #{_} for #{link}"
      end
    end
  end
end

if $0 == __FILE__
  fail unless ["https://i.imgur.com/BLCesav.jpg"] == Imgur::imgur_to_array("https://imgur.com/a/Aoh6l")
  %w{
    https://imgur.com/a/badlinkpattern
    http://example.com/
  }.each do |url|
    begin
      fail Imgur::imgur_to_array url
    rescue Imgur::Error => e
      raise unless e.to_s.start_with? "Imgur error: bad link pattern"
    end
  end
  exit


  print "self testing... "

  fail unless NetHTTPUtils.request_data("http://httpstat.us/200") == "200 OK"
  [400, 404, 500].each do |code|
    begin
      fail NetHTTPUtils.request_data "http://httpstat.us/#{code}"
    rescue NetHTTPUtils::Error => e
      raise if e.code != code
    end
  end
  fail unless NetHTTPUtils.get_response("http://httpstat.us/400").body == "400 Bad Request"
  fail unless NetHTTPUtils.get_response("http://httpstat.us/404").body == "404 Not Found"
  fail unless NetHTTPUtils.get_response("http://httpstat.us/500").body == "500 Internal Server Error"

  puts "OK #{__FILE__}"
end
