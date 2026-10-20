class SettingsController < ApplicationController
  def update
    warn = (params[:alert_warn].to_f * 100).round
    critical = (params[:alert_critical].to_f * 100).round
    if critical >= warn
      redirect_back_to_page root_path, alert: "Critical threshold must be below warning."
      return
    end
    Setting.set_alerts(warn:, critical:)
    redirect_back_to_page root_path, notice: "Alert thresholds updated."
  end
end
