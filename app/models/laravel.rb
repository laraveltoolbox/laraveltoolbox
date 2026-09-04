# frozen_string_literal: true

#
# Knowledge about how composer packages express their laravel compatibility.
#
module Laravel
  #
  # The runtime dependencies that pin a package to laravel versions. The
  # illuminate components are released in lockstep with laravel/framework, so
  # their constraints name laravel versions directly.
  #
  DEPENDENCY = %r{\A(laravel/framework|illuminate/[^/]+)\z}i

  #
  # The highest laravel major version we know about. Open-ended constraints
  # (`>=12.0`) describe an infinite set of versions, so they are enumerated up
  # to here - which means this needs bumping whenever a new laravel major is
  # released.
  #
  LATEST_VERSION = 13

  #
  # Packages commonly require several illuminate components with identical
  # constraints. For display we pick the most telling one instead of listing
  # them all.
  #
  PREFERRED_DEPENDENCIES = %w[laravel/framework illuminate/support illuminate/contracts].freeze

  #
  # The laravel major versions the given composer `require` hash supports.
  #
  # Composer AND-s separate requirements, so a package that requires
  # `illuminate/support: ^11.0|^12.0` alongside `illuminate/console: ^12.0`
  # only actually supports laravel 12.
  #
  def self.versions_for(requirements)
    constraints = requirements_for(requirements).values
    return [] if constraints.empty?

    constraints.map { Composer::Constraint.new(it, ceiling: LATEST_VERSION).major_versions }
               .reduce(:&)
               .sort
  end

  #
  # The raw constraint to display alongside the resolved versions, i.e. `^12.0|^13.0`
  #
  def self.requirement_for(requirements)
    laravel = requirements_for(requirements)
    return if laravel.empty?

    preferred = PREFERRED_DEPENDENCIES.find { laravel.key? it } || laravel.keys.min
    laravel.fetch preferred
  end

  def self.requirements_for(requirements)
    Hash(requirements).select { |name, _| name.match? DEPENDENCY }
  end
end
