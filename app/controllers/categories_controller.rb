class CategoriesController < ApplicationController
  def index
    @archived = params[:archived].present?
    @categories = Category.where(active: !@archived).includes(:children).order(:name)
    @grouped = Category::KINDS.index_with do |kind|
      tops, subs = @categories.select { |c| c.kind == kind }.partition { |c| c.parent_id.nil? }
      tops.map { |t| [ t, subs.select { |s| s.parent_id == t.id } ] }
    end
    @edit_category = Category.find_by(id: params[:edit])
    @parents = Category.active.top_level.order(:kind, :name)
  end

  def create
    category = Category.new(category_params)
    if category.save
      redirect_back_to_page categories_path, notice: "Category added."
    else
      redirect_back_to_page categories_path(new: 1), alert: category.errors.full_messages.to_sentence
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
    params.require(:category).permit(:name, :kind, :parent_id, :colour)
  end
end
