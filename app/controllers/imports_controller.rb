class ImportsController < ApplicationController
  def index
    @imports = Import.includes(:account, :user).order(created_at: :desc)
  end

  def new
    @accounts = Account.active.order(:name)
  end

  def create
    file = params[:file]
    if file.blank?
      redirect_to new_import_path, alert: "Choose a CSV file."
      return
    end
    import = Import.new(user: Current.user, account_id: params[:account_id],
                        filename: file.original_filename, payload: file.read)
    begin
      csv = CsvImport.new(import.payload)
      import.source_format = CsvImport.detect(csv.headers)
      import.mapping = CsvImport.suggest(csv.headers, import.source_format)
      import.save!
      redirect_to import, notice: "File parsed — check the preview, then commit."
    rescue CsvImport::ParseError => e
      redirect_to new_import_path, alert: "Couldn't parse that file: #{e.message}"
    end
  end

  def show
    @import = Import.find(params[:id])
    override = params.fetch(:mapping, {}).permit(:date, :payee, :amount, :debit, :credit, :balance, :sign, :sheet).to_h.compact_blank
    @mapping = override.presence || @import.mapping || {}
    @csv = CsvImport.new(@import.payload, sheet: @mapping["sheet"])
    @mapping = CsvImport.suggest(@csv.headers, @import.source_format).merge(@mapping)
    @preview = @csv.preview(@import, @mapping) if @mapping["date"].present? && (@mapping["amount"].present? || @mapping["debit"].present?)
  end

  def commit
    import = Import.find(params[:id])
    mapping = params.fetch(:mapping, {}).permit(:date, :payee, :amount, :debit, :credit, :balance, :sign, :sheet).to_h
    if mapping["date"].blank? || (mapping["amount"].blank? && mapping["debit"].blank?)
      redirect_to import, alert: "Map at least a date column and an amount (or debit/credit)."
      return
    end
    result = CsvImport.new(import.payload, sheet: mapping["sheet"])
                      .commit(import, mapping, set_balance: params[:set_balance].present?)
    redirect_to import, notice: "Imported #{result[:created]} transactions (#{result[:dupes]} skipped as duplicates)."
  end

  def destroy
    Import.find(params[:id]).destroy!
    redirect_to imports_path, notice: "Import and its transactions removed."
  end
end
