# frozen_string_literal: true

require "tmpdir"

RSpec.describe Rails::Schema::Renderer::HtmlGenerator do
  let(:id_column) do
    { name: "id", type: "integer", primary: true, nullable: false, default: nil }
  end

  let(:graph_data) do
    {
      nodes: [
        { id: "User", table_name: "users", columns: [id_column] },
        { id: "Post", table_name: "posts", columns: [id_column] }
      ],
      edges: [
        {
          from: "User", to: "Post", association_type: "has_many",
          label: "posts", foreign_key: "user_id",
          through: nil, polymorphic: false
        }
      ],
      metadata: {
        generated_at: "2026-01-01T00:00:00Z",
        model_count: 2, rails_version: nil
      }
    }
  end

  subject(:generator) { described_class.new(graph_data: graph_data) }

  describe "#render" do
    let(:html) { generator.render }

    it "returns an HTML string" do
      expect(html).to include("<!DOCTYPE html>")
      expect(html).to include("</html>")
    end

    it "includes the title" do
      expect(html).to include("Database Schema")
    end

    it "embeds the graph data" do
      expect(html).to include("__SCHEMA_DATA__")
      expect(html).to include('"User"')
      expect(html).to include('"Post"')
    end

    it "embeds CSS" do
      expect(html).to include("--bg-primary")
    end

    it "embeds d3 library" do
      expect(html).to include("d3")
    end

    it "embeds app.js" do
      expect(html).to include("__SCHEMA_DATA__")
    end

    it "escapes </ in JSON to prevent script injection" do
      data_with_slash = graph_data.dup
      data_with_slash[:nodes] = [
        { id: "</script>Evil", table_name: "test", columns: [] }
      ]
      gen = described_class.new(graph_data: data_with_slash)
      html = gen.render

      expect(html).not_to include("</script>Evil")
      expect(html).to include('<\\/script>Evil')
    end
  end

  describe "#render_to_file" do
    it "writes HTML to the configured path" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "output", "schema.html")
        generator.render_to_file(path)

        expect(File.exist?(path)).to be true
        expect(File.read(path)).to include("<!DOCTYPE html>")
      end
    end
  end
end
