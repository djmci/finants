require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "subcategory must match parent kind" do
    sub = Category.new(name: "Bonus", kind: "expense", parent: categories(:salary))
    assert_not sub.valid?
  end

  test "subcategory can't nest under a subcategory" do
    deep = Category.new(name: "Brunch", kind: "expense", parent: categories(:eating_out))
    assert_not deep.valid?
  end

  test "valid subcategory" do
    sub = Category.new(name: "Cafes", kind: "expense", parent: categories(:food))
    assert sub.valid?
  end
end
