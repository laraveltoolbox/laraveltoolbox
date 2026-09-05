# frozen_string_literal: true

#
# The index is written to continuously by ProjectSearchIndexJob, one project at
# a time, as projects are updated. These tasks cover the two things that job
# cannot do: configuring the index, and filling it from scratch.
#

# Meilisearch accepts large batches happily, but the request body has to stay
# within what the instance will read at once
IMPORT_BATCH_SIZE = 1_000

#
# Meilisearch's own default ordering, with the project score appended as the
# final tie breaker: between two libraries that match a query equally well, the
# more established one is the more useful answer.
#
RANKING_RULES = %w[words typo proximity attribute sort exactness score:desc].freeze

# The name carries far more signal than the description, and is listed first so
# meilisearch weights it higher
SEARCHABLE_ATTRIBUTES = %w[permalink description].freeze

# The permalink is all we read back - the records themselves are then loaded
# from postgres, so there is no point in shipping anything else
DISPLAYED_ATTRIBUTES = %w[permalink].freeze

def meili_client!
  MeiliSearch.client or abort "MEILI_SEARCH_URL is not set, nothing to talk to"
end

#
# Projects without a score are the ones nothing has been calculated for yet;
# they are excluded from search results anyway, so indexing them would only
# fill the index with entries no query can return.
#
def fill_index!(client)
  scope = Project.with_score.includes_associations
  total = scope.count
  done = 0

  scope.find_in_batches(batch_size: IMPORT_BATCH_SIZE) do |batch|
    client.store_documents :projects, ProjectSearchIndexJob.index_payload(*batch)
    done += batch.size
    puts "Queued #{done}/#{total} projects"
  end
end

namespace :meilisearch do
  desc "Apply the search index settings (ranking rules, searchable & displayed attributes)"
  task setup: :environment do
    client = meili_client!

    client.update_ranking_rules :projects, RANKING_RULES
    client.update_searchable_attributes :projects, SEARCHABLE_ATTRIBUTES
    client.update_displayed_attributes :projects, DISPLAYED_ATTRIBUTES

    puts "Index settings queued for update"
  end

  desc "Fill the search index with every scored project"
  task reindex: :environment do
    fill_index! meili_client!

    puts "Done. Meilisearch indexes asynchronously, so give it a moment to catch up."
  end

  desc "Show the current index settings"
  task settings: :environment do
    client = meili_client!

    puts "ranking rules:         #{client.ranking_rules(:projects).inspect}"
    puts "searchable attributes: #{client.searchable_attributes(:projects).inspect}"
    puts "displayed attributes:  #{client.displayed_attributes(:projects).inspect}"
  end
end
