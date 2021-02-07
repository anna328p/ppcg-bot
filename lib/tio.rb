require 'net/http'
require 'open-uri'
require 'json'
require 'nokogiri'
require 'zlib'

module TIO
  API_BASE = 'https://tio.run'

  def self.run_endpoint
    @@run_endpoint ||= URI.open(
      API_BASE + Nokogiri::HTML.parse(URI.open(API_BASE)).xpath('//head/script[2]/@src')[0]
    ).readlines.grep(/^var runURL/)[0][14..-4]
  end

  def self.gzdeflate(str)
    Zlib::Deflate.new(nil, -Zlib::MAX_WBITS).deflate(str, Zlib::FINISH)
  end

  def self.gzinflate(str)
    Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(str)
  end

  def self.languages
    JSON.parse URI.open("#{base}/languages.json").read
  end

  def self.languages_by_category(category)
    languages.filter { |k, v| v['categories'].include? category.to_s }
  end

  def self.file(name, body)
    "F#{name}\0#{body.size}\0#{body}"
  end

  def self.var(name, args)
    "V#{name}\0#{args.size}\0#{args.map { |a| "#{a}\0" }.join}"
  end

  def self.run(language, code, flags = nil, input = nil, arguments = [])
    args = '/' # purpose unknown

    val = ''
    val += var('lang', [language])
    val += var('args', arguments)
    val += var('TIO_OPTIONS', flags) if flags && !(language.start_with? 'java-')
    val += var('TIO_CFLAGS', flags) if flags
    val += file('.code.tio', code)
    val += file('.input.tio', input) if input
    val += 'R'

    req_body = gzdeflate(val)

    request_count = 0
    begin
      token = Random.new.bytes(16).chars.map { |c| c.ord.to_s(16) }.join
      uri_string = API_BASE + run_endpoint + args + token

      uri = URI(uri_string)
      post_res = Net::HTTP.post(uri, req_body)
      request_count += 1
      post_res.value
    rescue Net::HTTPServerException
      retry if request_count < 5
      raise
    end

    res = gzinflate(post_res.body[10..-1])

    res.split(res[0..15])[1..-1].map(&:chomp)
  end
end
