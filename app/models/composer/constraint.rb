# frozen_string_literal: true

module Composer
  #
  # Parses composer version constraints far enough to answer the two questions
  # this app cares about: which major versions of a dependency a package
  # supports, and the lowest version it accepts.
  #
  # This is deliberately not a complete implementation of composer's constraint
  # semantics. Every comparator is reduced to a range of major versions, which
  # are then intersected (for the AND parts of a constraint) and unioned (for
  # the OR parts). That covers the shapes that actually occur in the wild:
  #
  #   ^12.0|^13.0        ^11.0 || ^12.0 || ^13.0     12.*|13.*
  #   ^11.44.2 || ^13    >=12.0                      ~10.0
  #   >=8.2 <8.6         5.1.* || 5.2.*              ^7.1 | ^8.0
  #
  class Constraint
    # Composer separates alternatives with `|` or `||`
    OR_SEPARATOR = /\s*\|\|?\s*/

    #
    # A single comparator, i.e. `^12.0`, `>= 10.0` or `12.*`.
    #
    # Operator and version may be separated by whitespace (`>= 10.0`), which is
    # why the AND parts of a constraint (`>=8.2 <8.6`) cannot simply be split on
    # whitespace - we scan for comparators instead.
    #
    COMPARATOR = /
      (?<operator>[<>]=?|!=|==?|\^|~)?
      \s*
      v?
      (?<version>\d+(?:\.(?:\d+|\*|x))*|\*)
    /xi

    # Operators that place a lower bound on the accepted versions. A comparator
    # without an operator is an exact version, which bounds both ends.
    LOWER_BOUND_OPERATORS = [nil, "", "^", "~", ">=", ">", "=", "=="].freeze

    private attr_reader :constraint, :ceiling

    #
    # `ceiling` is the highest major version to enumerate for open-ended
    # constraints like `>=12.0`, which would otherwise describe an infinite set.
    #
    def initialize(constraint, ceiling: 0)
      @constraint = constraint.to_s
      @ceiling = ceiling
    end

    #
    # The major versions this constraint allows, sorted ascending. Empty when
    # the constraint is blank or cannot be satisfied at all.
    #
    def major_versions
      return [] if constraint.blank?

      constraint.split(OR_SEPARATOR).flat_map { majors_in it }.uniq.sort
    end

    #
    # The lowest version this constraint accepts as a `major.minor` string, or
    # nil when it has no lower bound at all.
    #
    def minimum_version
      candidates = comparators(constraint)
                   .select { LOWER_BOUND_OPERATORS.include? it[:operator] }
                   .map { it[:version] }
                   .reject { it == "*" }
      return if candidates.empty?

      format_version(candidates.min_by { segments it })
    end

    private

    #
    # The comparators within one OR clause are AND-ed by composer, so only the
    # versions all of them allow are actually supported.
    #
    def majors_in(clause)
      ranges = comparators(clause).map { range_for it }
      return [] if ranges.empty?

      low = ranges.map(&:first).max
      high = ranges.map(&:last).min

      low > high ? [] : (low..high).to_a
    end

    def comparators(string)
      string.to_enum(:scan, COMPARATOR).map { Regexp.last_match }
    end

    #
    # The inclusive range of major versions a single comparator allows.
    #
    # `^` and `~` both stay within one major version for our purposes (`^12.0`
    # is `>=12.0 <13.0`, `~10.0` is `>=10.0 <11.0`), as does an exact version or
    # a wildcard like `12.*`.
    #
    def range_for(match)
      version = match[:version]
      return [0, ceiling] if version == "*"

      major = version.to_i

      case match[:operator]
      when ">=", ">" then [major, ceiling]
      when "<=" then [0, major]
      when "<" then [0, highest_major_below(version, major)]
      when "!=" then [0, ceiling] # Exclusions are too rare to be worth modelling
      else [major, major]
      end
    end

    #
    # `<13.0` and `<13` both exclude every 13.x release, while `<13.5` still
    # allows 13.0 through 13.4.
    #
    def highest_major_below(version, major)
      version.split(".").drop(1).all? { it == "0" } ? major - 1 : major
    end

    def segments(version)
      version.split(".").map { it.match?(/\A\d+\z/) ? it.to_i : 0 }
    end

    def format_version(version)
      version.split(".").take_while { it.match?(/\A\d+\z/) }.first(2).join(".")
    end
  end
end
