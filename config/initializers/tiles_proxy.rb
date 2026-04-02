class TilesProxy < Rack::Proxy
  def perform_request(env)
    request = Rack::Request.new(env)
    if request.path =~ %r{^/tiles/}
      env["HTTP_HOST"] = "minipc.armandmgt.fr:8081"
      env["PATH_INFO"] = request.fullpath.gsub(%r{^/tiles/}, "/")
      env["content-length"] = nil
      super(env)
    else
      @app.call(env)
    end
  end

  def rewrite_response(triplet)
    _status, headers, _body = triplet
    headers["content-length"] = nil
    triplet
  end
end

Rails.application.config.middleware.use TilesProxy, { backend: "http://minipc.armandmgt.fr:8081", ssl_verify_none: true, read_timeout: 600 }
