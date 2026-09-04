# frozen_string_literal: true

#
# Composer package names are `vendor/name` pairs, which postgres' text search
# treats as a single file-path-like token. Searching for `permission` would
# hence not match `spatie/laravel-permission` by name at all.
#
# Replacing the slash before building the tsvector indexes both parts (and,
# thanks to the default parser's handling of hyphenated words, the individual
# words of the package name as well).
#
class IndexPermalinkPartsForSearch < ActiveRecord::Migration[8.1]
  def up
    update_trigger "replace(new.permalink, '/', ' ')"
  end

  def down
    update_trigger "new.permalink"
  end

  private

  def update_trigger(expression)
    create_trigger("projects_update_permalink_tsvector_trigger", compatibility: 1)
      .on(:projects).before(:insert, :update) do
      "new.permalink_tsvector := to_tsvector('pg_catalog.simple', coalesce(#{expression}, ''));"
    end

    # Re-index the existing records by triggering the (before update) trigger
    safety_assured { execute "UPDATE projects SET permalink = permalink" }
  end
end
