class HealthController < ApplicationController
  def show
    @report = HealthReport.new
  end
end
