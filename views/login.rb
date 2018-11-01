module Omnigollum
  module Views
    class Login < Mustache
      self.template_path = File.expand_path('../templates', __dir__)
      self.template_name = 'Login'

      attr_reader :title

      attr_reader :subtext

      def providers_active
        providers = []
        @auth[:providers].each do |name|
          provider_attr = {
            name: OmniAuth::Utils.camelize(name),
            provider_url: @auth[:route_prefix] + "/auth/#{name}" + (defined?(@auth_params) ? @auth_params : '')
          }
          name = name.to_s
          if has_logo?(logo_name = name) || (logo_name = @auth[:logo_missing])
            provider_attr[:image] = get_logo logo_name
            provider_attr[:image_alt]   = "#{provider_attr[:name]} logo"
            provider_attr[:image_title] = "Connect with #{provider_attr[:name]}"
          end
          providers.push provider_attr
        end
        providers
      end

      def has_logo?(name)
        File.exist?(@auth[:path_images] + '/' + name + @auth[:logo_suffix])
      end

      def get_logo(name)
        @auth[:route_prefix] + "/images/#{name}" + @auth[:logo_suffix]
      end
    end
  end
end
