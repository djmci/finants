module DollarField
  extend ActiveSupport::Concern

  class_methods do
    # Form-facing dollars accessor for an `attr_cents` integer column.
    def dollar_field(attr)
      cents_attr = "#{attr}_cents"
      define_method(attr) { public_send(cents_attr).to_i / 100.0 }
      define_method("#{attr}=") do |dollars|
        public_send("#{cents_attr}=", if dollars.is_a?(Numeric)
          (dollars * 100).round
        elsif dollars.to_s.strip.match?(/\A-?\d+(\.\d+)?\z/)
          (BigDecimal(dollars.to_s) * 100).round.to_i
        end)
      end
    end
  end
end
