# Replaces Net::HTTP.new for the duration of a block with a fake that records the request,
# for testing notification channels without network access.
module HttpStubHelper
  def with_stubbed_http(fake)
    original = Net::HTTP.method(:new)
    Net::HTTP.singleton_class.define_method(:new) do |host, port|
      fake.host = host
      fake.port = port
      fake
    end
    yield
  ensure
    Net::HTTP.singleton_class.define_method(:new, original)
  end

  class CapturingHttp
    attr_accessor :host, :port, :use_ssl, :open_timeout, :read_timeout
    attr_reader :last_request

    def initialize(code: "200", body: "ok")
      @code = code
      @body = body
    end

    def request(request)
      @last_request = request
      response = Net::HTTPResponse::CODE_TO_OBJ.fetch(@code).new("1.1", @code, "stub")
      body = @body
      response.define_singleton_method(:body) { body }
      response
    end

    def json
      JSON.parse(@last_request.body)
    end
  end
end
