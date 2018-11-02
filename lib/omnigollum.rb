require 'cgi'
require 'omniauth'
require 'mustache/sinatra'
require 'sinatra/base'

module Omnigollum
  module Views; class Layout < Mustache; end; end
  module Models
    class OmniauthUserInitError < StandardError; end

    class User
      attr_reader :uid, :name, :email, :nickname, :provider
    end

    class OmniauthUser < User
      def initialize(hash, options)
        sleep 1
        # Validity checks, don't trust providers
        @uid = hash['uid'].to_s.strip
        raise OmniauthUserInitError, 'Insufficient data from authentication provider, uid not provided or empty' if @uid.empty?

        @nickname = hash['info']['nickname'].to_s.strip if hash['info'].key?('nickname')

        @name = hash['info']['name'].to_s.strip if hash['info'].key?('name')
        @name = @nickname if !@name || @name.empty?
        @name = options[:default_name] if !@name || @name.empty?

        raise OmniauthUserInitError, 'Insufficient data from authentication provider, name not provided or empty' if !@name || @name.empty?

        @email = hash['info']['email'].to_s.strip if hash['info'].key?('email')
        @email = options[:default_email] if !@email || @email.empty?

        raise OmniauthUserInitError, 'Insufficient data from authentication provider, email not provided or empty' if !@email || @email.empty?

        @provider = hash['provider']

        self
      end
    end
  end

  module Helpers
    def user_authed?
      session.key? :omniauth_user
    end

    def user_auth
      @title   = 'Authentication is required'
      @subtext = 'Please choose a login service'
      show_login
    end

    def kick_back
      redirect !request.referrer.nil? && request.referrer !~ /#{Regexp.escape(settings.send(:omnigollum)[:route_prefix])}\/.*/ ?
        request.referrer :
        '/'
      halt
    end

    def get_user
      session[:omniauth_user]
    end

    def user_deauth
      session.delete :omniauth_user
    end

    def auth_config
      options = settings.send(:omnigollum)

      @auth = {
        route_prefix: options[:route_prefix],
        providers: options[:provider_names],
        path_images: options[:path_images],
        logo_suffix: options[:logo_suffix],
        logo_missing: options[:logo_missing]
      }
    end

    def show_login
      options = settings.send(:omnigollum)

      # Don't bother showing the login screen, just redirect
      if options[:provider_names].count == 1
        origin = if !request.params['origin'].nil?
                   request.params['origin']
                 elsif !request.path.nil?
                   request.path
                 else
                   '/'
                 end

        redirect (request.script_name || '') + options[:route_prefix] + '/auth/' + options[:provider_names].first.to_s + '?origin=' +
                 CGI.escape(origin)
      else
        auth_config
        require options[:path_views] + '/login'
        halt mustache Omnigollum::Views::Login
      end
    end

    def show_error
      options = settings.send(:omnigollum)
      auth_config
      require options[:path_views] + '/error'
      halt mustache Omnigollum::Views::Error
    end

    def commit_message
      if user_authed?
        user = get_user
        { message: params[:message], name: user.name, email: user.email }
      else
        { message: params[:message] }
      end
    end
  end

  # Config class provides default values for omnigollum configuration, and an array
  # of all providers which have been enabled if a omniauth config block is passed to
  # eval_omniauth_config.
  class Config
    attr_accessor :default_options
    class << self; attr_accessor :default_options; end

    @default_options = {
      protected_routes: [
        '/revert/*',
        '/revert',
        '/create/*',
        '/create',
        '/edit/*',
        '/edit',
        '/rename/*',
        '/rename/',
        '/upload/*',
        '/upload/',
        '/delete/*',
        '/delete'
      ],

      route_prefix: '/__omnigollum__',
      dummy_auth: true,
      providers: proc { provider :github, '', '' },
      path_base: dir = File.expand_path(File.dirname(__FILE__) + '/..'),
      logo_suffix: '_logo.png',
      logo_missing: 'omniauth', # Set to false to disable missing logos
      path_images: "#{dir}/public/images",
      path_views: "#{dir}/views",
      path_templates: "#{dir}/templates",
      default_name: nil,
      default_email: nil,
      provider_names: [],
      authorized_users: [],
      author_format: proc { |user| user.nickname ? user.name + ' (' + user.nickname + ')' : user.name },
      author_email: proc { |user| user.email }
    }

    def initialize
      @default_options = self.class.default_options
    end

    # Register provider name
    #
    # name - Provider symbol
    # args - Arbitrary arguments
    def provider(name, *_args)
      @default_options[:provider_names].push name
    end

    # Evaluate procedure calls in an omniauth config block/proc in the context
    # of this class.
    #
    # This allows us to learn about omniauth config items that would otherwise be inaccessible.
    #
    # block - Omniauth proc or block
    def eval_omniauth_config(&block)
      instance_eval(&block)
    end

    # Catches missing methods we haven't implemented, but which omniauth accepts
    # in its config block.
    #
    # args - Arbitrary list of arguments
    def method_missing(*args); end
  end

  module Sinatra
    def self.registered(app)
      # As options determine which routes are created, they must be set before registering omniauth
      config  = Omnigollum::Config.new

      options = app.settings.respond_to?(:omnigollum) ?
        config.default_options.merge(app.settings.send(:omnigollum)) :
        config.default_options

      # Set omniauth path prefix based on options
      OmniAuth.config.path_prefix = options[:route_prefix] + OmniAuth.config.path_prefix

      # Setup test_mode options
      if options[:dummy_auth]
        OmniAuth.config.test_mode = true
        OmniAuth.config.mock_auth[:default] = {
          'uid' => '12345',
          'info' => {
            'email' => 'user@example.com',
            'name' => 'example user'
          },
          'provider' => 'local'
        }
        end
      # Register helpers
      app.helpers Helpers

      # Enable sinatra session support
      app.set :sessions, true

      # Setup omniauth providers
      unless options[:providers].nil?
        app.use OmniAuth::Builder, &options[:providers]

        # You told omniauth, now tell us!
        config.eval_omniauth_config &options[:providers] if options[:provider_names].count == 0
      end

      # Populates instance variables used to display currently logged in user
      app.before '/*' do
        @user_authed = user_authed?
        @user        = get_user
      end

      # Stop browsers from screwing up our referrer information
      # FIXME: This is hacky...
      app.before '/favicon.ico' do
        halt 403 unless user_authed?
      end

      # Explicit login (user followed login link) clears previous redirect info
      app.before options[:route_prefix] + '/login' do
        kick_back if user_authed?
        @auth_params = "?origin=#{CGI.escape(request.referrer)}" unless request.referrer.nil?
        user_auth
      end

      app.before options[:route_prefix] + '/logout' do
        user_deauth
        kick_back
      end

      app.before options[:route_prefix] + '/auth/failure' do
        user_deauth
        @title = 'Authentication failed'
        @subtext = "Provider did not validate your credentials (#{params[:message]}) - please retry or choose another login service"
        @auth_params = "?origin=#{CGI.escape(request.env['omniauth.origin'])}" unless request.env['omniauth.origin'].nil?
        show_error
      end

      app.before options[:route_prefix] + '/auth/:name/callback' do
        begin
          if !request.env['omniauth.auth'].nil?
            user = Omnigollum::Models::OmniauthUser.new(request.env['omniauth.auth'], options)

            case (authorized_users = options[:authorized_users])
            when Regexp
              user_authorized = (user.email =~ authorized_users)
            when Array
              user_authorized = authorized_users.include?(user.email) || authorized_users.include?(user.nickname)
            else
              user_authorized = true
            end

            # Check authorized users
            unless user_authorized
              @title   = 'Authorization failed'
              @subtext = 'User was not found in the authorized users list'
              @auth_params = "?origin=#{CGI.escape(request.env['omniauth.origin'])}" unless request.env['omniauth.origin'].nil?
              show_error
            end

            session[:omniauth_user] = user

            # Update gollum's author hash, so commits are recorded correctly
            session['gollum.author'] = {
              name: options[:author_format].call(user),
              email: options[:author_email].call(user)
            }

            redirect request.env['omniauth.origin']
          elsif !user_authed?
            @title   = 'Authentication failed'
            @subtext = 'Omniauth experienced an error processing your request'
            @auth_params = "?origin=#{CGI.escape(request.env['omniauth.origin'])}" unless request.env['omniauth.origin'].nil?
            show_error
          end
        rescue StandardError => fail_reason
          @title   = 'Authentication failed'
          @subtext = fail_reason
          @auth_params = "?origin=#{CGI.escape(request.env['omniauth.origin'])}" unless request.env['omniauth.origin'].nil?
          show_error
        end
      end

      app.before options[:route_prefix] + '/images/:image.png' do
        content_type :png
        send_file options[:path_images] + '/' + params[:image] + '.png'
      end

      # Stop sinatra processing and hand off to omniauth
      app.before options[:route_prefix] + '/auth/:provider' do
        halt 404
      end

      # Pre-empt protected routes
      options[:protected_routes].each { |route| app.before(route) { user_auth unless user_authed? } }

      # Write the actual config back to the app instance
      app.set(:omnigollum, options)
    end
  end
end
