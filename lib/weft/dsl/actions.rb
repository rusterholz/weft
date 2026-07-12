# frozen_string_literal: true

module Weft
  module DSL
    # Mixin for classes that declare user-initiated actions: `performs`,
    # `transfers`, and the `dismisses` sugar. Included into Weft::Component.
    module Actions
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declare a user-initiated action on this component.
        #
        #   performs :advance do |attrs|
        #     order = Order.find(attrs.order_id)
        #     Oms::PrepareOrder.call(order)
        #   end
        #
        #   performs method: :delete, swap: :delete do |attrs| ... end
        def performs(name = nil, method: :post, swap: :outer_html, target: nil, &block)
          action = Weft::Action.new(name: name, method: method, swap: swap,
                                    target: target, renders: self, callable: block)
          own_actions[[name, method]] = action
        end

        # Sugar for performs with swap: :delete. Removes the component from
        # the DOM on success. The callable (if given) runs for side effects;
        # the return value is rendered but htmx ignores the response body.
        #
        #   dismisses :close                          # no side effects
        #   dismisses :remove do |attrs|              # with side effects
        #     Item.find(attrs.item_id).archive!
        #   end
        def dismisses(name = nil, method: :delete, &)
          performs(name, method: method, swap: :delete, &)
        end

        # Declare a transfer — an action that renders a different component.
        #
        #   transfers :edit, to: EditableOrderHeader do |attrs|
        #     { mode: "full" }
        #   end
        def transfers(name = nil, to:, method: :post, swap: :outer_html, target: nil, &block)
          action = Weft::Action.new(name: name, method: method, swap: swap,
                                    target: target, renders: to, callable: block)
          own_actions[[name, method]] = action
        end

        # All declared actions (own + inherited), keyed by [name, method].
        def actions
          if superclass.respond_to?(:actions)
            superclass.actions.merge(own_actions)
          else
            own_actions.dup
          end
        end

        # Look up an action by name (for Context interception).
        def action_for(name)
          actions.values.find { |a| a.name == name }
        end

        private

        def own_actions
          @own_actions ||= {}
        end
      end
    end
  end
end
