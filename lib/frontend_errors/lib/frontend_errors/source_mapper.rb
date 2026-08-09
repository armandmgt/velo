# frozen_string_literal: true

require "uri"

module FrontendErrors
  # Resolves the URL of a served asset back to the source file it was built from.
  #
  # No source maps are involved and none are needed: with importmap + Propshaft
  # there is no bundling or minification, so line numbers in the served asset
  # match the source file exactly. All that has to be undone is the digest
  # Propshaft splices into the filename (application-abc12345.js).
  #
  # Returning an absolute path under Rails.root is what lets an error backend
  # recognise the frame as application code and show the surrounding source.
  class SourceMapper
    MAX_CACHE_SIZE = 500

    def initialize(host: nil)
      @host = host
      @cache = {}
    end

    # @return [String, nil] absolute path of the source file, if it can be found
    def resolve(url)
      return nil if url.nil?

      @cache.fetch(url) do
        path = lookup(url)
        @cache.clear if @cache.size >= MAX_CACHE_SIZE
        @cache[url] = path
      end
    end

    private
      def lookup(url)
        path = asset_path(url)
        return nil unless path

        logical_path, _digest = Propshaft::Asset.extract_path_and_digest(path)
        asset = Rails.application.assets.load_path.find(logical_path)
        asset&.path&.to_s
      rescue StandardError
        # Never let stack rewriting take down the report itself.
        nil
      end

      # The path under the asset prefix, or nil when the URL isn't one of our
      # assets (a CDN, an inline script, a browser extension, another origin).
      def asset_path(url)
        return nil unless defined?(Propshaft) && defined?(Rails) && Rails.respond_to?(:application)

        uri = URI.parse(url)
        return nil if uri.host && @host && uri.host != @host
        return nil unless uri.path&.start_with?(assets_prefix)

        uri.path.delete_prefix(assets_prefix)
      rescue URI::InvalidURIError
        nil
      end

      def assets_prefix
        @assets_prefix ||= Rails.application.assets.prefix
      end
  end
end
