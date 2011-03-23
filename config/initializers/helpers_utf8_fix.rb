# Keywords: Rails 2.3, Ruby 1.9
# Error:    invalid byte sequence in US-ASCII
# Error:    incompatible character encodings: UTF-8 and ASCII-8BIT
#
# This patch overwrites every ActionView::Helpers::TagHelper
# method and the "value" and "value_before_type_cast" methods
# of ActionView::Helpers::InstanceTag, to force the UTF8
# encoding on their return value, if applicable.
# 
# This is done because the source encoding of Rails' files is
# ASCII-8BIT, thus strings generated in the tag helpers are
# automatically tagged with that encoding, moreover FormHelper
# and RailsXss do all kinds of nasty stuff manipulating strings,
# rendering them UNUSABLE if you really accept UTF8-encoded
# strings from your web clients.
#
# See http://blog.grayproductions.net/articles/ruby_19s_three_default_encodings
# and http://yehudakatz.com/2010/05/17/encodings-unabridged/ and of course
# http://unicode.org/ to understand what we're talking about.
#
# It is *useless* with Rails3, thus it is activated only on
# Rails2. String#force_utf8 is available here, even if it's
# not a good place to put it:
#
#  https://github.com/Panmind/zendesk/blob/fa0af09/lib/panmind/string_force_utf8_patch.rb
#
# DISCLAIMER: YMMV, NO WARRANTY, BSD LICENSE.
#
# Spinned off http://panmind.org/
#
#   - vjt  Tue Nov  9 19:21:29 CET 2010
#

if Rails::VERSION::MAJOR == 2

  # Change view helpers to return UTF-8 strings
  #
  module ActionView::Helpers
    module UTF8Coercion
      extend self

      def patch(target, methods)
        methods.each {|meth| override(meth, target)}
      end

      def override(method, target)
        patched = "#{method}_with_utf8_coercion"
        wrapper = wrapper_for "#{method}_without_utf8_coercion"

        target.instance_eval do
          define_method patched, &wrapper
          alias_method_chain method, :utf8_coercion
        end
      end

      def wrapper_for(method)
        lambda do |*args, &block|
          send(method, *args, &block).tap do |string|
            if string.respond_to?(:force_utf8)
              #UTF8Coercion.debug method, string
              string.force_utf8
              #UTF8Coercion.debug method, string
            end
          end
        end
      end

      #def debug(method, string)
      #  method  = method[0..-23] # strip _without_utf8_coercion
      #  excerpt = string[0, 40].gsub /\s+/, ' '

      #  printf "[%22s] %-40s %5s %s\n", method, excerpt, !!string.html_safe?, string.encoding
      #end

    end

    UTF8Coercion.patch(TagHelper, TagHelper.instance_methods)
    UTF8Coercion.patch(InstanceTag.metaclass, [:value, :value_before_type_cast])
  end

  # Change html_escape to force UTF-8 on each passed string
  #
  module ERB::Util
    class << self
      def html_escape_with_utf8(s)
        html_escape_without_utf8(s.force_utf8)
      end
      alias_method_chain :html_escape, :utf8
    end
  end

  require 'rack/utils'   # Overkill, but here
  require 'rack/request' # just for reference

  # Mangle all incoming parameters transcoding them to UTF-8
  # Assume UTF-8 if the request has no attached charset.
  #
  class Utf8EnforcerMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      req = Rack::Request.new(env)

      enc = req.content_charset
      # YES, ASSUME UTF-8.
      enc = 'UTF-8' if enc.blank?

      mangle(req.params, enc)
      @app.call(req.env)
    end

    private
      def mangle(hsh, encoding)
        hsh.each do |k,v|
          if v.respond_to?(:force_encoding)
            # Set the encoding specified in the request
            v.force_encoding(encoding)

            # Transcode to UTF-8 unless already UTF-8
            v.encode!('UTF-8') unless v.encoding == Encoding::UTF_8

          elsif v.kind_of?(Hash)
            mangle(v, encoding) # Recurse
          end
        end
      end

    ActionController::Dispatcher.middleware.insert_before(Rack::Head, self)
    puts '** UTF8 Enforcer: inserted before Rack::Head'
  end

end
