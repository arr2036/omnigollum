module Omnigollum
  module Views
    class Error < Mustache
      self.template_path = File.expand_path("../../templates", __FILE__)
      self.template_name = 'Error'
      
      def title
        @title
      end
      
      def subtext
        @subtext
      end

      def loginurl
        @auth[:route_prefix] + 'login' + (defined?(@auth_params) ? @auth_params : '')
      end
    end
  end
end
