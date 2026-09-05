# frozen_string_literal: true

class TrendsController < ApplicationController
  def index
    latest_date = Package::Trend::Navigation.latest_date
    if latest_date
      redirect_to action: :show, id: latest_date
    else
      # A fresh instance has no download history yet, and trends need several
      # weeks of it before the first ranking can be calculated
      render :unavailable
    end
  end

  def show
    @navigation = Package::Trend::Navigation.find(params.expect(:id))
    redirect_to id: @navigation.date unless @navigation.exact_match?(params[:id])

    @trends = Package::Trend.for_date(@navigation.date)
  end
end
