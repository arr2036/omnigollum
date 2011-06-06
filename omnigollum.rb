require 'cgi'
require 'omniauth'
require 'mustache/sinatra'
require 'sinatra/base'

module Omnigollum
  module Views; class Layout < Mustache; end; end
  module Models
    class User
      attr_reader :uid, :name, :email, :provider
    end 
      
    class DummyUser < User
      def initialize (uid = '1234567', name = 'example', email = 'example@example.org')
        @uid      = uid
        @name     = name
        @email    = email
        @provider = 'local'
        self
      end
    end
      
    class OmniauthUser < User
      def initialize (hash)
        # Validity checks, don't trust providers 
        @uid = hash['uid']
        raise "Invalid data from provider, omniauth user hash {:uid => } must not be empty or whitespace" if @uid.to_s.trim.empty?
    
        @name = hash['user_info']['name'].to_s.trim
        raise "Invalid data from provider, omniauth user hash {:user_info => {:name => }} must not be empty or whitespace" if @name.empty?
    
        @email    = hash['user_info']['email'].to_s.trim if hash['user_info'].has_key?('email')
        @provider = hash['provider']
        self
      end
    end    
  end
  
  module Helpers
    def user_authed?
      session.has_key?('auth.user')
    end
  
    def user_auth
      session['auth.origin'] = request.path_info
      redirect '/auth/' 
    end
  
    def get_user
      session['auth.user']
    end
  
    def user_deauth
      session.delete('auth.user')
    end
    
    # Because omnigollum templates are in a different location to gollum templates,
    # we need to pre compile/instantiate them with omnigollum paths.
    # 
    # template - Template symbol
    # 
    # Returns mustache view class
    def omnigollum_view(template)
      options = settings.send(:omnigollum)
       
      mustache_class(:login, {:templates => options[:path_templates], :views => options[:path_views], :namespace => Omnigollum})
    end
    
    def auth_config
      options = settings.send(:omnigollum)
      
      @auth = {
        :providers    => options[:provider_names],
        :path_images  => options[:path_images],
        :logo_suffix  => options[:logo_suffix],
        :logo_missing => options[:logo_missing]
      }
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
    attr_accessor :provider_name_mirror
    class << self; attr_accessor :default_options; end  
      
    @default_options = {
      :protected_routes => [
      '/revert/*',
      '/revert',
      '/create/*',
      '/create',
      '/edit/*',
      '/edit'],
      
      :dummy_auth   => false,
      :providers    => nil,
      :path_base    => dir = File.dirname(File.expand_path(__FILE__)),
      :logo_suffix  => "_logo.png",
      :logo_missing => "omniauth", # Set to false to disable missing logos
      :path_images  => "#{dir}/public/images/",
      :path_views   => "#{dir}/views",
      :path_templates => "#{dir}/templates",
      :provider_names => nil 
    }
      
    def initialize
      @provider_name_mirror = []
    end
    
    # Register provider name
    # 
    # name - Provider symbol
    # args - Arbitrary arguments
    def provider(name, *args)
      @provider_name_mirror.push name
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
      config  = Omnigollum::Config.new()
      
      options = config.class.default_options.merge(app.settings.send(:omnigollum)) if app.settings.respond_to?(:omnigollum)
      
      app.helpers Helpers
      
      # Enable sinatra session support
      app.set :sessions,  true
      
      # Setup omniauth providers
      if !options[:providers].nil?
        app.use OmniAuth::Builder, &options[:providers]
        
        # You told omniauth, now tell us!
        if options[:provider_names].nil?
          config.eval_omniauth_config(&options[:providers])
          options[:provider_names] = config.provider_name_mirror
        end
      end
      
      # Write the actual config back to the app instance
      app.set(:omnigollum, options)
      
      # Pre-empt protected routes
      options[:protected_routes].each { |route| app.before(route) { user_auth unless user_authed? }}
      
      # Propulates instance variables used to display currently logged in user
      app.before '/*' do
        @user_authed     = user_authed?
        @user            = get_user
      end
     
      app.before '/auth/*' do
        @auth = {
          :providers    => config.provider_name_mirror,
          :path_images  => options[:path_images],
          :logo_suffix  => options[:logo_suffix],
          :logo_missing => options[:logo_missing]
        } 
      end
      
      # Register static routes to serve omniauth content
      app.get '/auth/' do
        if user_authed?
          redirect('/')
        else
          @title = 'Authentication is required'
          auth_config
          mustache(omnigollum_view(:login))
        end
      end
      
      app.get '/auth/failure' do
        user_deauth
        @title = 'Authentication failed'  
        auth_config
        mustache(omnigollum_view(:login))
      end
      
      app.get '/auth/logout' do
        user_deauth
        redirect '/'
      end
  
      app.get '/auth/:name/callback' do
        session['auth.user'] = Omnigollum::Models::OmniauthUser.new(request.env['omniauth.auth'])
        redirect session.has_key?('auth.origin') ? session['auth.origin'] : '/'
      end
      
      app.get '/__omnigollum__/:image.png' do
        content_type :png
        send_file options[:path_images] + params[:image] + '.png'
      end
      
      if options[:dummy_auth] || options[:providers].nil?
        app.get '/auth/:provider' do
          session['auth.user'] = Omnigollum::Models::DummyUser.new
          redirect session.has_key?('auth.origin') ? session['auth.origin'] : '/'
        end
      else
        # Stop sinatra processing and hand off to omniauth
        app.get('/auth/:provider') { halt 404 }
      end
    end
  end
end