# frozen_string_literal: true

module Weft
  # Render-tree navigation for components and pages: reach an ancestor — or self —
  # in the Arbre tree by type or tag, to read its identity (class, weft_id, route,
  # page path). This is the "child affects ancestor" affordance: a nested
  # component discovers what it needs to target instead of being hand-fed its
  # parent's identity.
  #
  # Mixed into Weft::Component and Weft::Page; call inside `build`. (There is no
  # instance, and no render tree to walk, inside a verb block.) Lean on the
  # ancestor's identity and params — fixed at construction — rather than state its
  # own `build` may not have set yet, since it is mid-build above you.
  module Traversal
    # The nearest node matching +matcher+, self included, walking up the tree —
    # impedance-matched to the DOM's Element.closest(): include-self,
    # nearest-first, nil if none.
    #
    #   closest(Weft::Page)                     # nearest enclosing page
    #   closest(OrdersPanel)                    # nearest panel of that type
    #   closest(Paginatable)                    # nearest node playing that role
    #   closest(:div)                           # nearest <div> (self included)
    #   closest(Weft::Component) { |c| c.params.key?(:order_id) }  # refined
    #
    # +matcher+ is a Class/Module (matched is_a?, subclass- and include-inclusive)
    # or a Symbol (matched against tag_name). An optional block refines: a
    # candidate must match the positional AND the block. Returns the matching
    # Arbre node — a component for a class match, a plain element for a tag — or nil.
    def closest(matcher, include_self: true, &refine)
      unless matcher.is_a?(Module) || matcher.is_a?(Symbol)
        raise ArgumentError,
              "closest matcher must be a Class, Module, or Symbol tag name (got #{matcher.class})"
      end

      node = include_self ? self : parent
      while node
        return node if traversal_match?(node, matcher, refine)

        node = node.parent
      end
      nil
    end

    # closest strictly above self (self excluded) — the expressive read for
    # "reach my enclosing X". Does not take include_self; use closest for that.
    def enclosing(matcher, &) = closest(matcher, include_self: false, &)

    # closest that raises Weft::AncestorNotFound instead of returning nil — for a
    # component that requires the ancestor (pair with dependent!).
    def closest!(matcher, include_self: true, &)
      closest(matcher, include_self: include_self, &) ||
        raise(Weft::AncestorNotFound,
              "no #{matcher.inspect} #{include_self ? 'at or above' : 'above'} #{self.class}")
    end

    # enclosing that raises instead of returning nil.
    def enclosing!(matcher, &) = closest!(matcher, include_self: false, &)

    private

    def traversal_match?(node, matcher, refine)
      matched =
        if matcher.is_a?(Symbol)
          node.respond_to?(:tag_name) && node.tag_name.to_s == matcher.to_s
        else
          node.is_a?(matcher)
        end
      matched && (refine.nil? || refine.call(node))
    end
  end
end
