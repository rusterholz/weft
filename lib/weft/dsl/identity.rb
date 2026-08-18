# frozen_string_literal: true

module Weft
  module DSL
    # Mixin for classes that declare which of their params compose their
    # identity. Included into Weft::Component.
    #
    # See Weft::Component#identifies_by for the DSL surface.
    module Identity
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declare which params identify this component — the values its DOM id
        # is built from, in the order they appear in the id.
        #
        #   identifies_by :order_id
        #   identifies_by :order_id, :line_item_id   # => "line-item-row-6-3"
        #
        # Identity is declared at the component, not marked on a param,
        # because the same inherited param identifies one component and not
        # another. A subclass's declaration REPLACES its ancestor's rather
        # than adding to it — otherwise identity would inherit silently and a
        # subclass would be back to having no say over it.
        #
        # A component that declares nothing has no identity of its own: its id
        # is its class name alone. Declare `unique!` to be handed one.
        def identifies_by(*names)
          @own_identifiers = names
        end

        # The params composing this component's identity (own, else inherited).
        def identifiers
          return @own_identifiers if instance_variable_defined?(:@own_identifiers)
          return superclass.identifiers if superclass.respond_to?(:identifiers)

          []
        end
      end
    end
  end
end
