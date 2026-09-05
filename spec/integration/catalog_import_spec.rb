# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogImport, :clean_database do
  fixtures :all

  let(:catalog_data) { Oj.load Rails.root.join("lib", "base-catalog.json").read }

  let(:category_data) { catalog_data["category_groups"].pluck("categories").flatten }

  let(:project_permalinks) do
    %w[barryvdh/laravel-debugbar laravel/scout laravel/telescope spatie/laravel-backup spatie/laravel-medialibrary]
  end

  let(:import) { described_class.new(catalog_data) }

  before do
    Project.create! permalink: "laravel/scout"
    Project.create! permalink: "spatie/laravel-backup"
    Project.create! permalink: "spatie/laravel-medialibrary"
  end

  describe "perform" do
    it "creates all category groups" do
      expect { import.perform }.to change(CategoryGroup, :count).to(catalog_data["category_groups"].count)
    end

    it "results in expected set of category groups" do
      import.perform
      actual = CategoryGroup.pluck(:permalink)
      expected = catalog_data["category_groups"].pluck("permalink")
      expect(actual).to match_array(expected)
    end

    it "applies expected attributes to imported category groups" do
      import.perform
      group_data = catalog_data["category_groups"].sample
      expect(CategoryGroup.find(group_data["permalink"]))
        .to have_attributes group_data.slice("name", "permalink", "description")
    end

    it "removes obsolete category groups" do
      obsolete_group = CategoryGroup.create! permalink: "Obsolete", name: "Obsolete"

      expect { import.perform }.to change { CategoryGroup.find_by(permalink: obsolete_group.permalink) }.to(nil)
    end

    it "creates all categories" do
      expect { import.perform }.to change(Category, :count).to(category_data.count)
    end

    it "results in expected set of categories" do
      import.perform
      actual = Category.pluck(:permalink)
      expected = category_data.pluck("permalink")
      expect(actual).to match_array(expected)
    end

    it "applies expected attributes to imported categories" do
      import.perform
      sample_data = category_data.sample
      expect(Category.find(sample_data["permalink"]))
        .to have_attributes sample_data.slice("name", "permalink", "description")
    end

    it "removes obsolete categories" do
      import.perform

      obsolete_category = Category.create! permalink:      "Obsolete",
                                           name:           "Obsolete",
                                           category_group: CategoryGroup.first

      expect { import.perform }.to change { Category.find_by(permalink: obsolete_category.permalink) }.to(nil)
    end

    it "creates projects that are not known locally yet" do
      expect { import.perform }.to change(Project, :count).by(2)
    end

    it "results in expected set of projects" do
      import.perform
      expect(Project.pluck(:permalink)).to match_array(project_permalinks)
    end

    it "assigns projects to all of their categories" do
      import.perform
      expect(Project.all.map { |p| p.categories.count }).to all(be > 0)
    end

    it "removes categorizations from existing categorized projects" do
      import.perform
      project = Project.create! permalink: "foo_project", categories: [Category.first]

      expect { import.perform }.to change { project.categories.count }.from(1).to(0)
    end

    #
    # Catalog entries name github repositories as well as composer packages, so
    # a project record is created for each of them. Dropping the entry used to
    # leave that record behind forever, with nothing left to display.
    #
    it "removes projects the catalog no longer references" do
      import.perform
      obsolete = Project.create! permalink: "vendor/dropped-from-catalog"

      expect { import.perform }.to change { Project.exists? obsolete.permalink }.to(false)
    end

    #
    # Those belong to the package sync, which drops them when they go missing
    # from packagist - the catalog has no say over them
    #
    it "keeps projects backed by a mirrored package" do
      import.perform
      Factories.package "vendor/mirrored"
      Project.create! permalink: "vendor/mirrored", package_name: "vendor/mirrored"

      expect { import.perform }.not_to(change { Project.exists? "vendor/mirrored" })
    end

    #
    # A catalog that fetched but carries nothing is a broken import, and reading
    # it as "every github-only project is obsolete" would empty the table
    #
    context "when the catalog references no projects at all" do
      let(:catalog_data) do
        super().tap do |data|
          data["category_groups"].each { |group| group["categories"].each { |c| c["projects"] = [] } }
        end
      end

      it "leaves the existing projects alone" do
        expect { import.perform }.not_to change(Project, :count)
      end
    end
  end
end
