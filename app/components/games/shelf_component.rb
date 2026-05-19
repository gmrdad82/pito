# Backward-compat alias for the legacy `Games::ShelfComponent` namespace.
# The canonical class lives at `app/components/shelf_component.rb` after
# the top-level rename on 2026-05-19 (so non-/games surfaces like
# /channels Wave A1 can reuse the chrome). /games is a closed polish
# milestone — this alias keeps its view files byte-identical against
# the pre-rename state while resolving to the same class object.
module Games
  ShelfComponent = ::ShelfComponent
end
