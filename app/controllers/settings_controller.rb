class SettingsController < ApplicationController
  def edit
    @setting = Setting.current
  end

  def update
    @setting = Setting.current

    if @setting.update(setting_params)
      redirect_to edit_settings_path, notice: "Settings were successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def setting_params
      params.expect(setting: [ :ping_retention_days ])
    end
end
