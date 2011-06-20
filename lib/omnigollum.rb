require 'cgi'
require 'omniauth'
require 'mustache/sinatra'
require 'sinatra/base'

module Omnigollum
  module Views; class Layout < Mustache; end; end
  module Models
    class OmniauthUserInitError < StandardError; end
    
    class User
      attr_reader :uid, :name, :email, :provider
    end 
    
    class OmniauthUser < User
      def initialize (hash)
        # Validity checks, don't trust providers 
        @uid = hash['uid']
        raise OmniauthUserInitError, "Invalid data from provider, 'uid' must not be empty or whitespace" if @uid.to_s.strip.empty?
    
        @name = hash['user_info']['name'].to_s.strip
        raise OmniauthUserInitError, "Invalid data from provider, 'user_info => name' must not be empty or whitespace" if @name.empty?
    
        @email    = hash['user_info']['email'].to_s.strip if hash['user_info'].has_key?('email')
        @provider = hash['provider']
        self
      end
    end    
  end
  
  module Helpers
    def user_authed?
      session.has_key? :auth_user
    end
  
    def user_auth
      @title   = 'Authentication is required'
      @subtext = 'Please choose a login service'
      show_login
    end
    
    def kick_back
      redirect !request.referrer.nil? && request.referrer !~ /#{Regexp.escape(settings.send(:omnigollum)[:route_prefix])}\/.*/ ?
        request.referrer:
        '/'
      halt
    end
  
    def get_user
      session[:auth_user]
    end
  
    def user_deauth
      session.delete :auth_user
    end
    
    def auth_config
      options = settings.send(:omnigollum)
      
      @auth = {
        :route_prefix => options[:route_prefix],
        :providers    => options[:provider_names],
        :path_images  => options[:path_images],
        :logo_suffix  => options[:logo_suffix],
        :logo_missing => options[:logo_missing]
      }
    end
    
    def show_login
      auth_config
      require settings.send(:omnigollum)[:path_views] + '/login'
      halt mustache Omnigollum::Views::Login
    end

    def commit_message
      if user_authed?
        user = get_user
        return { :message => params[:message], :name => user.name, :email => user.email}
      else
        return { :message => params[:message]}
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
      :protected_routes => [
      '/revert/*',
      '/revert',
      '/create/*',
      '/create',
      '/edit/*',
      '/edit'],
      
      :route_prefix => '/__omnigollum__',
      :dummy_auth   => true,
      :providers    => Proc.new { provider :github, '', '' },
      :path_base    => dir = File.dirname(File.expand_path(__FILE__)),
      :logo_suffix  => "_logo.png",
      :logo_missing => "omniauth", # Set to false to disable missing logos
      :path_images  => "#{dir}/public/images",
      :path_views   => "#{dir}/views",
      :path_templates => "#{dir}/templates",
      :provider_names => []
    }
      
    def initialize
      @default_options = self.class.default_options
    end
    
    # Register provider name
    # 
    # name - Provider symbol
    # args - Arbitrary arguments
    def provider(name, *args)
      @default_options[:provider_names].push name
    end
    
    # Evaluate procedure calls in an omniauth config block/proc in the context
    # of this class.
    #
    # This allows us to learn about omniauth config items that would otherwise be inaccessible.
    #
    # block - Omniauth proc or block
    def eval_omniauth_config(&block)
      self.instance_eval(&block)
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
            "user_info" => {
            "email"  => "user@example.com",
            "name"   => "example user"
          },
          'provider' => 'local'
        }
      end
      # Register helpers
      app.helpers Helpers
      
      # Enable sinatra session support
      app.set :sessions,  true
      
      # Setup omniauth providers
      if !options[:providers].nil?
        app.use OmniAuth::Builder, &options[:providers]
        
        # You told omniauth, now tell us!
        config.eval_omniauth_config &options[:providers] if options[:provider_names].count == 0
      end
      
      # Pre-empt protected routes
      options[:protected_routes].each { |route| app.before(route) { user_auth unless user_authed? }}
      
      # Populates instance variables used to display currently logged in user
      app.before '/*' do
        @user_authed = user_authed?
        @user        = get_user
      end
      
      # Explicit login (user followed login link) clears previous redirect info
      app.before options[:route_prefix] + '/login' do
        kick_back if user_authed?
        @auth_params = "?origin=#{CGI.escape(request.referrer)}" if !request.referrer.nil?
        user_auth
      end
      
      app.before options[:route_prefix] + '/logout' do
        user_deauth
        kick_back
      end
      
      app.before options[:route_prefix] + '/auth/failure' do
        user_deauth
        @title    = 'Authentication failed'
        @subtext = 'Provider did not validate your credentials (#{param[:message]}) - please retry or choose another login service'
        @auth_params = "?origin=#{CGI.escape(request.env['omniauth.origin'])}" if !request.env['omniauth.origin'].nil?
        show_login
      end

      app.before options[:route_prefix] + '/auth/:name/callback' do
        begin
          if !request.env['omniauth.auth'].nil? 
            session[:auth_user] = Omnigollum::Models::OmniauthUser.new(request.env['omniauth.auth'])            
            redirect request.env['omniauth.origin']
          elsif !user_authed?
            @title    = 'Authentication failed'
            @subtext = "Omniauth experienced an error processing your request"
            @auth_params = "?origin=#{CGI.escape(request.env['omniauth.origin'])}" if !request.env['omniauth.origin'].nil?
            show_login
          end
        rescue Omnigollum::Models::OmniauthUserInitError => fail_reason
          @title    = 'Authentication failed'
          @subtext = fail_reason
          @auth_params = "?origin=#{CGI.escape(request.env['omniauth.origin'])}" if !request.env['omniauth.origin'].nil?
          show_login
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

      # Write the actual config back to the app instance
      app.set(:omnigollum, options)
    end
  end
end