# frozen_string_literal: true

module Weft
  module DSL
    # Mixin for the `adds_children_to :@ivar` macro — generates the standard
    # Arbre container override that redirects user-block children into a
    # nested element while letting structural children (added during `build`)
    # pass through to the wrapper.
    #
    # Mixed into both Weft::Component and Weft::Page by default. Usable on
    # any class that inherits from Arbre::Component.
    #
    #   class Card < Weft::Component
    #     adds_children_to :@body
    #
    #     def build(attributes = {})
    #       super
    #       h2 "Header"            # structural — goes to wrapper
    #       @body = div(class: "card-body")
    #     end
    #   end
    #
    # The `:@body` form (with the leading `@`) is required — a pedagogical
    # cue that the macro depends on the user assigning the ivar somewhere
    # in `build`. If `build` returns without setting the ivar and a child
    # is then added, the macro raises with a pointed error message.
    module Containers
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declare that block-style children should be added to the named
        # instance variable instead of the wrapper element itself.
        def adds_children_to(ivar)
          unless ivar.is_a?(Symbol)
            raise ArgumentError,
                  "adds_children_to expects a Symbol (e.g., :@body), got #{ivar.inspect}"
          end
          unless ivar.to_s.start_with?("@")
            raise Weft::InvalidDefinition,
                  "adds_children_to expects a Symbol that must start with @ (e.g., :@body), got #{ivar.inspect}"
          end

          prepend(Containers.behavior_for(ivar))
        end
      end

      # Build the prepended Module that implements both the `build` wrap
      # (to detect "build returned without assigning the ivar") and the
      # `add_child` redirect. Each call returns a fresh anonymous module
      # — declaring the macro on multiple classes is safe.
      def self.behavior_for(ivar)
        Module.new do
          define_method(:build) do |*args, **kwargs|
            super(*args, **kwargs)
            @_weft_container_built = true
          end

          define_method(:add_child) do |child|
            target = instance_variable_defined?(ivar) ? instance_variable_get(ivar) : nil
            if target
              target << child
            elsif @_weft_container_built
              raise Weft::MissingContainerIvar,
                    "#{self.class} declared `adds_children_to #{ivar.inspect}` " \
                    "but never assigned #{ivar} in build " \
                    "(e.g., #{ivar} = div(class: 'body') inside build)"
            else
              super(child)
            end
          end
        end
      end
    end
  end
end
