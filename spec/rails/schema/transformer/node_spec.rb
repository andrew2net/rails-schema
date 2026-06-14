# frozen_string_literal: true

RSpec.describe Rails::Schema::Transformer::Node do
  describe "#to_h" do
    it "includes group when non-empty" do
      node = described_class.new(id: "User", table_name: "users", group: ["Admin"])

      expect(node.to_h[:group]).to eq(["Admin"])
    end

    it "omits group when empty" do
      node = described_class.new(id: "User", table_name: "users")

      expect(node.to_h).not_to have_key(:group)
    end

    it "includes view: true when the node is a view" do
      node = described_class.new(id: "Message", table_name: "messages", view: true)

      expect(node.to_h[:view]).to be true
    end

    it "omits view when false" do
      node = described_class.new(id: "User", table_name: "users")

      expect(node.to_h).not_to have_key(:view)
    end
  end
end
