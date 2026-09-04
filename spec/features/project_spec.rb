# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project Display" do
  fixtures :all

  it "can display Project README" do
    project = Factories.project "widgets"

    visit "/projects/#{project.permalink}"
    expect(page).to have_css(".hero")
    expect(page).to have_no_css(".readme .content")

    project.github_repo.create_readme! html: "<strong>some content</strong>", etag: "1234"
    visit "/projects/#{project.permalink}"

    expect(page).to have_css(".readme .content")

    within ".readme .content" do
      expect(page).to have_text("some content")
    end
  end

  it "shows which laravel and php versions the package supports" do
    project = Factories.project "widgets"

    visit "/projects/#{project.permalink}"
    expect(page).to have_css(".hero")
    expect(page).to have_no_css(".project-compatibility")

    project.package.update! laravel_versions:    [11, 12, Laravel::LATEST_VERSION],
                            laravel_requirement: "^11.0|^12.0|^13.0",
                            php_requirement:     "^8.2",
                            php_minimum_version: "8.2"

    visit "/projects/#{project.permalink}"

    within ".project-compatibility" do
      expect(page).to have_text "Laravel 11 – #{Laravel::LATEST_VERSION}"
      expect(page).to have_text "PHP 8.2+"
    end

    # Packages that keep up with the current laravel major are called out
    expect(page).to have_css ".project-compatibility-tag.supports-latest"
  end

  it "can display a project's reverse dependencies", :js do
    project = Project.find("illuminate/support")

    visit "/projects/#{project.permalink}"

    within '.metric[data-metric-name="package_reverse_dependencies_count"]' do
      page.find("a.button").click
    end

    within ".hero" do
      expect(page).to have_text "Reverse Dependencies for illuminate/support"
    end

    expect_display_mode "Compact"
    take_snapshots! "Reverse Dependencies: Compact View"

    shown_dependencies = page.all(".project.box h3").map(&:text)

    project.reverse_dependencies.then do |expected|
      expect(shown_dependencies).to eq expected.map(&:name)
    end

    change_display_mode "Full"
    change_display_mode "Table"
  end
end
