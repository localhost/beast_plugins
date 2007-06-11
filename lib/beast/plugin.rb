module Beast
  # This module assists with general Mephisto plugins.
  class Plugin
    attr_reader :options

    @@plugins       = []
    @@custom_routes = []
    @@view_paths    = {}
    @@tabs          = []
    cattr_reader :plugins, :custom_routes, :view_paths, :tabs

    def initialize
      @options = default_options.dup
      yield self if block_given?
      install_routes!
    end
    
    def install_routes!
      mapper = ActionController::Routing::RouteSet::Mapper.new(ActionController::Routing::Routes)
      self.class.custom_routes.each do |args|
        mapper.send *args
      end
    end

    class << self
      def initialize_plugins(*plugins)
        require 'dispatcher'
        Dispatcher.to_prepare :load_beast_plugins do
          require 'application' unless Object.const_defined?(:ApplicationController)
          ApplicationHelper.module_eval do
            def head_extras
              Beast::Plugin.plugins.collect { |p| p.head_extras.to_s } * "\n"
            end
          end
          
          Beast::Plugin.plugins.clear
          plugins.each do |plugin|
            plugin.to_s.classify.constantize.configure
          end
          yield if block_given?
        end
      end

      def plugin_name
        @plugin_name ||= name.demodulize.underscore
      end

      def plugin_path
        @plugin_path ||= File.join(RAILS_ROOT, 'vendor', 'beast', plugin_name)
      end

      plugin_property_source = %w(author version homepage notes).collect! do |property|
        <<-END
          def #{property}(value = nil)
            @#{property} = value if value
            @#{property}
          end
        END
      end
      eval plugin_property_source * "\n"

      def configure(&block)
        self.plugins << new(&block)
      end

      def default_options
        @default_options ||= {}
      end
      
      def option(property, default, field_type = :text_field)
        class_eval <<-END, __FILE__, __LINE__
            def #{property}
              write_attribute(:options, {}) if read_attribute(:options).nil?
              options[#{property.inspect}].blank? ? #{default.inspect} : options[#{property.inspect}]
            end
            
            def #{property}=(value)
              write_attribute(:options, {}) if read_attribute(:options).nil?
              options[#{property.inspect}] = value
            end
          END
        default_options[property] = field_type
      end
  
      # Installs the plugin's tables using the schema file in lib/#{plugin_name}/schema.rb
      #
      #   script/runner -e production 'FooPlugin.install'
      #   => installs the FooPlugin plugin.
      #
      def install
        self::Schema.install
      end
      
      # Uninstalls the plugin's tables using the schema file in lib/#{plugin_name}/schema.rb
      def uninstall
        self::Schema.uninstall
      end
      
      # Adds a custom route to Mephisto from a plugin.  These routes are created in the order they are added.  
      # They will be the last routes before the Mephisto Dispatcher catch-all route.
      def route(*args)
        custom_routes << args
      end
      
      def resources(resource, options = {})
        route :resources, resource, options
        controller resource.to_s.humanize, resource
      end
      
      def resource(resource, options = {})
        route :resource, resource, options
        controller resource.to_s.humanize, resource
      end
  
      # Keeps track of custom adminstration tabs.  Each item is an array of arguments to be passed to link_to.
      #
      #   class Foo < Beast::Plugin
      #     tab 'Foo', :controller => 'foo'
      #   end
      def tab(*args)
        tabs << args
      end

      # Sets up a custom controller.  Beast::Plugin.public_controller is used for the basic setup.  This also automatically
      # adds a tab for you, and symlinks Mephisto's core app/views/layouts path.  Like Beast::Plugin.public_controller, this should be
      # called from your plugin's init.rb file.
      #
      #   class Foo < Beast::Plugin
      #     controller 'Foo', 'foo'
      #   end
      #
      #   class FooController < ApplicationController
      #     prepend_view_path Beast::Plugin.view_paths[:foo]
      #     ...
      #   end
      #
      # Your views will then be stored in #{YOUR_PLUGIN}/views/admin/foo/*.rhtml.
      def controller(title, name = nil, options = {})
        returning (name || title.underscore).to_sym do |controller_name|
          view_paths[controller_name] = File.join(plugin_path, 'views').to_s
          tab title, {:controller => controller_name.to_s}.update(options)
        end
      end
    end
    
    def head_extras
      @head_extras ||= 
        (css_files.collect { |f| %(<link href="#{sanitize_path f}" rel="stylesheet" type="text/css" />) } * "\n") + 
        (js_files.collect  { |f| %(<script src="#{sanitize_path f}" type="text/javascript"></script>)   } * "\n")
    end
  
    route :connect, ':asset/:plugin/*paths', :asset => /images|javascripts|stylesheets/, :controller => 'beast/assets', :action => 'show'

    plugin_property_source = %w(author version homepage notes plugin_name plugin_path default_options).collect! do |property|
      "def #{property}() self.class.#{property} end"
    end
    eval plugin_property_source * "\n"
    
    protected
      def css_files
        @css_files ||= Dir[File.join(plugin_path, 'public', 'stylesheets', '*.css')]
      end
      
      def js_files
        @js_files ||= Dir[File.join(plugin_path, 'public', 'javascripts', '*.js')]
      end
      
      def sanitize_path(path)
        sanitized = path[plugin_path.size + 7..-1]
        sanitized.gsub! /^\/([^\/]+)\// do |path|
          path << plugin_name << '/'
        end
      end
  end
end