class Shared::Navbar < Bridgetown::Component
  attr_reader :metadata, :resource, :navigation

  def initialize(metadata:, resource:, navigation:)
    @metadata, @resource, @navigation = metadata, resource, navigation
  end
end
