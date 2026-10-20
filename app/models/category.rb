class Category < ApplicationRecord
  KINDS = %w[income expense].freeze

  belongs_to :parent, class_name: "Category", optional: true
  has_many :children, class_name: "Category", foreign_key: :parent_id, dependent: :nullify
  has_many :transactions, dependent: :nullify

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validate :parent_is_same_kind_top_level

  scope :active, -> { where(active: true) }
  scope :top_level, -> { where(parent_id: nil) }

  def display_name
    parent ? "#{parent.name} / #{name}" : name
  end

  private

  # One level of nesting only, and children inherit the parent's kind.
  def parent_is_same_kind_top_level
    return unless parent
    errors.add(:parent, "can't itself be a subcategory") if parent.parent_id.present?
    errors.add(:parent, "must be the same kind") if parent.kind != kind
  end
end
