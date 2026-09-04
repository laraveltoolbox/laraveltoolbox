# frozen_string_literal: true

class TrendsController < ApplicationController
  def index
    latest_date = Package::Trend::Navigation.latest_date
    if latest_date
      redirect_to action: :show, id: latest_date
    else
      # This would normally only happen on a local, empty database
      render plain: "No stats data is available, please seed the database"
    end
  end

  def show
    @navigation = Package::Trend::Navigation.find(params.expect(:id))
    redirect_to id: @navigation.date unless @navigation.exact_match?(params[:id])

    @trends = Package::Trend.for_date(@navigation.date)
  end
end
