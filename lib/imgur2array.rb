# v = Gem.loaded_specs["nethttputils"].version
# raise Gem::DependencyError, "expecting nethttputils version #{v} ~> 0.0.7.1" unless Gem::Requirement::OPS["~>"].call v, Gem::Version.create("0.0.7.0")

module Imgur
  class << self
    attr_accessor :logger
  end
  self.logger = Object.new.tap do |o|
    o.define_singleton_method :error, &method(:puts)
  end

  class Error < RuntimeError
    def initialize body
      Module.nesting[1].logger.error "Imgur error: #{body}"
      super "Imgur error: #{body}"
    end
  end

  require "nethttputils"
  require "json"
  def self.imgur_to_array link
    fail "env var missing -- IMGUR_CLIENT_ID" unless ENV["IMGUR_CLIENT_ID"]

    case link
    when /\Ahttps?:\/\/((m|i|www)\.)?imgur\.com\/(a|gallery)\/[a-zA-Z0-9]{5}(#[a-zA-Z0-9]{2})?\z/,
         /\Ahttps?:\/\/imgur\.com\/gallery\/[a-zA-Z0-9]{5}\/new\z/
      fail link.inspect unless /\/(?<type>a|gallery)\/(?<id>[a-zA-Z0-9]{5})/ =~ link
      timeout = 1
      json = begin
        NetHTTPUtils.request_data "https://api.imgur.com/3/#{
          # type == "gallery" ? "gallery" : "album"
          "album"
        }/#{id}/0.json",
          header: { Authorization: "Client-ID #{ENV["IMGUR_CLIENT_ID"]}" }
      rescue NetHTTPUtils::Error => e
        case e.code
        when 404 ; return
        when 500
          logger.error "sleeping #{timeout} seconds because of Imgur HTTP error #500"
          sleep timeout
          timeout *= 2
          retry
        end
      end
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
        # one day single-video item should hit this
        fail data_imgur.inspect
      end
    when /\/\/i\./,
         /\Ahttps?:\/\/((m|www)\.)?imgur\.com\/(gallery\/|r\/[A-Za-z0-9][A-Za-z0-9_]{2,20}\/)?[a-zA-Z0-9]{5}([a-zA-Z0-9]{2})?(\?r|\?third_party=1#_=_|\/new|\.jpg|\.gifv|\.mp4)?\z/
      json = begin
        NetHTTPUtils.request_data "https://api.imgur.com/3/image/#{
          link[/(?<=\/)[a-zA-Z0-9]{5}([a-zA-Z0-9]{2})?(?=(\?r|\?third_party=1#_=_|\/new|\.(?:jpg|gifv|mp4|png))?\z)/] || fail(link)
        }/0.json",
          header: { Authorization: "Client-ID #{ENV["IMGUR_CLIENT_ID"]}" }
      rescue NetHTTPUtils::Error => e
        fail unless e.code == 404
        return
      end
      [ JSON.load(json)["data"] ]
    when /\Ahttps:\/\/imgur\.com\/[a-zA-Z0-9]{5}\z/
      # TODO rescue like in two places above?
      json = NetHTTPUtils.request_data "https://api.imgur.com/3/image/#{
        link[/(?<=\/)[a-zA-Z0-9]{5}\z/]
      }/0.json",
        header: { Authorization: "Client-ID #{ENV["IMGUR_CLIENT_ID"]}" }
      [ JSON.load(json)["data"] ]
    else
      raise Error.new "bad link pattern #{link.inspect}"
    end.map do |_|
      case _["type"]
      when "image/jpeg", "image/png", "image/gif", "video/mp4"
        _.values_at "link", "width", "height", "type"
      else
        raise Error.new "unknown type of #{link}: #{_}"
      end
    end
  end
end

if $0 == __FILE__
  STDOUT.sync = true
  puts "self testing..."

  %w{
    https://imgur.com/a/badlinkpattern
    http://example.com/
    https://imgur.com/gallery/YO49F.
  }.each do |url|
    begin
      fail Imgur::imgur_to_array url
    rescue Imgur::Error => e
      raise unless e.to_s.start_with? "Imgur error: bad link pattern \""
    end
  end

  require "minitest/mock"
  VALID_IMGUR_IMAGE_URL = "https://i.imgur.com/BLCesav.jpg"
  fail unless [["https://i.imgur.com/BLCesav.jpg", 1000, 1500, "image/jpeg"]] == Imgur::imgur_to_array(VALID_IMGUR_IMAGE_URL)
  fail unless nil == (( NetHTTPUtils.stub :request_data, ->*{ raise NetHTTPUtils::Error.new "", 404 } do
    Imgur::imgur_to_array VALID_IMGUR_IMAGE_URL
  end ))
  begin
    fail (( NetHTTPUtils.stub :request_data, ->*{ raise NetHTTPUtils::Error.new "", 400 } do
      Imgur::imgur_to_array VALID_IMGUR_IMAGE_URL
    end ))
  rescue NetHTTPUtils::Error
  end

  [
    ["https://imgur.com/a/Aoh6l", "https://i.imgur.com/BLCesav.jpg", 1000, 1500, "image/jpeg"],
    ["http://i.imgur.com/7xcxxkR.gifv", "http://i.imgur.com/7xcxxkRh.gif", 718, 404, "image/gif"],
    ["https://imgur.com/9yaMdJq", "https://i.imgur.com/9yaMdJq.mp4", 720, 404, "video/mp4"],
    ["http://imgur.com/gallery/dCQprEq/new", "https://i.imgur.com/dCQprEq.jpg"],
    ["http://imgur.com/HQHBBBD", "https://i.imgur.com/HQHBBBD.jpg"], # http
    ["https://imgur.com/BGDh6eu", "https://i.imgur.com/BGDh6eu.jpg"], # https
    ["https://imgur.com/a/qNCOo", 6, "https://i.imgur.com/vwqfi3s.jpg", "https://i.imgur.com/CnSMWvo.jpg"], # https album
    ["http://imgur.com/a/0MiUo", 49, "https://i.imgur.com/kJ1jrjO.jpg", "https://i.imgur.com/TMQJARX.jpg"], # album, zoomable
    ["http://imgur.com/a/WswMg", 20, "https://i.imgur.com/Bt3RWV7.png", "https://i.imgur.com/sRc2lqN.png"], # album image, not zoomable
    ["http://imgur.com/a/AdJUK", 3, "https://i.imgur.com/Yunpxnx.jpg", "https://i.imgur.com/2epn2nT.jpg"], # needs https because of authorship # WAT?
    ["http://imgur.com/gallery/vR4Am", 7, "https://i.imgur.com/yuUQI25.jpg", "https://i.imgur.com/RdxyAMQ.jpg"],
    ["http://imgur.com/gallery/qP2RQtL", "https://i.imgur.com/qP2RQtL.png"], # single image gallery?
    ["http://imgur.com/gallery/jm0OKQM", "https://i.imgur.com/jm0OKQM.gif"],
    ["http://imgur.com/gallery/nKAwE/new", 28, "https://i.imgur.com/VQhR8hB.jpg", "https://i.imgur.com/axlzNRL.jpg"],
    ["http://m.imgur.com/rarOohr", "https://i.imgur.com/rarOohr.jpg"],
    ["http://imgur.com/r/wallpaper/j39dKMi", "https://i.imgur.com/j39dKMi.jpg"],
    ["http://imgur.com/gallery/oZXfZ", 12, "https://i.imgur.com/t7RjRXU.jpg", "https://i.imgur.com/anlPrvS.jpg"],
    ["http://imgur.com/gallery/dCQprEq/new", "https://i.imgur.com/dCQprEq.jpg", 5760, 3840, "image/jpeg"],
    ["https://imgur.com/S5u2xRB?third_party=1#_=_", "https://i.imgur.com/S5u2xRB.jpg", 2448, 2448, "image/jpeg"],
    ["https://imgur.com/3eThW", "https://i.imgur.com/3eThW.jpg", 2560, 1600, "image/jpeg"],
    ["https://i.imgur.com/RGO6i.mp4", "https://i.imgur.com/RGO6i.gif", 339, 397, "image/gif"]
  ].each do |url, n = nil, first = nil, last = nil, type = nil|
    # next (fail if Imgur::imgur_to_array url) unless n
    real = Imgur::imgur_to_array url
    case last
    when NilClass
      fail [url, real].inspect unless real.size == 1 && real.first.first == n
    when Numeric
      fail [url, real].inspect unless real.size == 1 && real.first == [n, first, last, type]
    when String
      fail [url, real.size].inspect unless real.size == n
      fail [url, real.first].inspect unless real.first.first == first
      fail [url, real.last].inspect unless real.last.first == last
    else
      fail
    end
  end

  puts "OK #{__FILE__}"
  exit
end
