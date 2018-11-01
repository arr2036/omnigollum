module Omnigollum
  module Views
    class Error < Mustache
      self.template_path = File.expand_path('../templates', __dir__)
      self.template_name = 'Error'

      attr_reader :title

      attr_reader :subtext

      def loginurl
        @auth[:route_prefix] + 'login' + (defined?(@auth_params) ? @auth_params : '')
      end
    end
  end
end
