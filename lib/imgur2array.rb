module Imgur
  class << self
    attr_accessor :logger
  end
  self.logger = Object.new.tap do |o|
    o.define_singleton_method :error, &method(:puts)
  end

  class Error < RuntimeError
    def initialize body
      Module.nesting[1].logger.error body
      super "Imgur error: #{body}"
    end
  end

  require "nethttputils"
  require "json"
  def self.imgur_to_array link
    fail "env var missing -- IMGUR_CLIENT_ID" unless ENV["IMGUR_CLIENT_ID"]

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
  puts "self testing..."

  # fail unless ["https://i.imgur.com/BLCesav.jpg"] == Imgur::imgur_to_array("https://imgur.com/a/Aoh6l")
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

  [
    # ["http://i.imgur.com/7xcxxkR.gifv", "http://i.imgur.com/7xcxxkRh.gif"], # gif
    # ["http://imgur.com/HQHBBBD", "https://i.imgur.com/HQHBBBD.jpg"], # http
    # ["https://imgur.com/BGDh6eu", "https://i.imgur.com/BGDh6eu.jpg"], # https
    # ["https://imgur.com/a/qNCOo", "https://i.imgur.com/vwqfi3s.jpg", "https://i.imgur.com/CnSMWvo.jpg", 6], # https album
    # ["http://imgur.com/a/0MiUo", "https://i.imgur.com/kJ1jrjO.jpg", "https://i.imgur.com/TMQJARX.jpg", 49], # album, zoomable
    # ["http://imgur.com/a/WswMg", "https://i.imgur.com/Bt3RWV7.png", "https://i.imgur.com/sRc2lqN.png", 20], # album image, not zoomable
    # ["http://imgur.com/a/AdJUK", "https://i.imgur.com/Yunpxnx.jpg", "https://i.imgur.com/2epn2nT.jpg", 3], # needs https because of authorship # WAT?
    
    # ["http://imgur.com/gallery/nKAwE/new", "http://i.imgur.com/VQhR8hB.jpg"],
    # ["http://imgur.com/gallery/vR4Am", "http://i.imgur.com/ydDUl4z.jpg"],
    # ["http://imgur.com/gallery/qP2RQtL", "http://i.imgur.com/qP2RQtL.png"], # single image gallery?
    # ["http://m.imgur.com/rarOohr", "http://m.imgur.com/rarOohr.jpg"],
    # ["http://imgur.com/r/wallpaper/j39dKMi", "http://imgur.com/j39dKMi.jpg"],
    # ["http://imgur.com/r/wallpaper/rZ37ZYN", "http://imgur.com/j39dKMi.jpg"],
    # ["http://imgur.com/gallery/jm0OKQM", "http://imgur.com/j39dKMi.jpg"],
    # ["http://imgur.com/gallery/oZXfZ", ""],
  ].each do |url, first, last = nil, n = nil|
    real = Imgur::imgur_to_array url
    unless n
      fail [url, real].inspect unless real == Array(first)
    else
      fail [url, real.size].inspect unless real.size == n
      fail [url, real.first].inspect unless real.first == first
      fail [url, real.last].inspect unless real.last == last
    end
  end

  puts "OK #{__FILE__}"
  exit
end
