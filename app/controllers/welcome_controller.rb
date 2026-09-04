# frozen_string_literal: true

class WelcomeController < ApplicationController
  def home
    @featured_categories = Category.featured
    @trending_projects = Package::Trend.latest.limit(8)
    @stats = Stats.new
  end
end
