# frozen_string_literal: true

class Stats
  def projects_with_categories_count
    @projects_with_categories_count ||= Project.joins(:categories).count
  end

  def packages_count
    @packages_count ||= Package.count
  end

  def categories_count
    @categories_count ||= Category.count
  end
end
