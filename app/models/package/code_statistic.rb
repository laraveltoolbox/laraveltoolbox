# frozen_string_literal: true

#
# Persistence for lines of code statistics.
#
# See also PackageCodeStatsService
#
class Package::CodeStatistic < ApplicationRecord
  belongs_to :package,
             primary_key: :name,
             foreign_key: :package_name,
             inverse_of:  :code_statistics
end
