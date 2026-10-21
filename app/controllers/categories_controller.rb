class CategoriesController < ApplicationController
  def index
    @tab = params[:tab].presence_in(%w[expense income rules]) || "expense"
    @archived = params[:archived].present?
    @categories = Category.where(active: !@archived).includes(:children).order(:name)
    @grouped = Category::KINDS.index_with do |kind|
      tops, subs = @categories.select { |c| c.kind == kind }.partition { |c| c.parent_id.nil? }
      tops.map { |t| [ t, subs.select { |s| s.parent_id == t.id } ] }
    end
    @edit_category = Category.find_by(id: params[:edit])
    @parents = Category.active.top_level.order(:kind, :name)
    @payee_rules = PayeeRule.includes(:category).order(:pattern, :id)
    @edit_rule = PayeeRule.find_by(id: params[:edit_rule])
  end

  # Mini form for inline creation inside a form drawer — or the
  # plain link when cancelling.
  def new
    if params[:cancel]
      render partial: "new_link", locals: { select_id: params[:select_id] }
    else
      @category = Category.new(kind: params[:kind] || "expense")
      render partial: "new_inline", locals: { category: @category, select_id: params[:select_id] }
    end
  end

  def create
    category = Category.new(category_params)
    if category.save
      respond_to do |format|
        # select_id is only sent by the inline drawer mini-form —
        # the real category drawer needs a normal redirect back.
        format.turbo_stream do
          if params[:select_id].present?
            @category = category; @select_id = params[:select_id]
          else
            redirect_back_to_page categories_path, notice: "Category added."
          end
        end
        format.html { redirect_back_to_page categories_path, notice: "Category added." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          if params[:select_id].present?
            render turbo_stream: turbo_stream.replace("new_category_frame",
              partial: "new_inline", locals: { category:, select_id: params[:select_id] }),
              status: :unprocessable_entity
          else
            redirect_back_to_page categories_path(new: 1), alert: category.errors.full_messages.to_sentence
          end
        end
        format.html { redirect_back_to_page categories_path(new: 1), alert: category.errors.full_messages.to_sentence }
      end
    end
  end

  def update
    category = Category.find(params[:id])
    if category.update(category_params)
      redirect_back_to_page categories_path, notice: "Category saved."
    else
      redirect_back_to_page categories_path(edit: category.id), alert: category.errors.full_messages.to_sentence
    end
  end

  def archive
    Category.find(params[:id]).update!(active: false)
    redirect_back_to_page categories_path, notice: "Category archived."
  end

  def unarchive
    Category.find(params[:id]).update!(active: true)
    redirect_back_to_page categories_path, notice: "Category restored."
  end

  private

  def category_params
    params.require(:category).permit(:name, :kind, :parent_id, :exclude_from_forecast)
  end
end
