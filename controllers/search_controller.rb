require 'cgi'

class SearchController < ApplicationController
  namespace "/search" do
    # execute a search query
    get do
      process_search()
    end

    post do
      process_search()
    end

    private

    def process_search(params=nil)
      params ||= @params
      text = params["q"]

      query = get_edismax_query(text, params)
      #puts "Edismax query: #{query}, params: #{params}"
      set_page_params(params)

      docs = Array.new
      resp = LinkedData::Models::Class.search(query, params)
      total_found = resp["response"]["numFound"]

      resp["response"]["docs"].each do |doc|
        doc = doc.symbolize_keys
        resource_id = doc[:resource_id]
        doc.delete :resource_id
        doc[:id] = resource_id
        # TODO: The `rescue next` on the following line shouldn't be here
        # However, at some point we didn't store the ontologyId in the index
        # and these records haven't been cleared out so this is getting skipped
        ontology_uri = doc[:ontologyId].first.sub(/\/submissions\/.*/, "") rescue next
        ontology = LinkedData::Models::Ontology.read_only(id: ontology_uri, acronym: doc[:submissionAcronym])
        submission = LinkedData::Models::OntologySubmission.read_only(id: doc[:ontologyId], ontology: ontology)
        doc[:submission] = submission
        doc[:ontology_rank] = LinkedData::OntologiesAPI.settings.ontology_rank[doc[:submissionAcronym]] || 0
        instance = LinkedData::Models::Class.read_only(doc)
        docs.push(instance)
      end

      docs.sort! {|a, b| [b[:score], b[:ontology_rank]] <=> [a[:score], a[:ontology_rank]]}

      #need to return a Page object
      page = page_object(docs, total_found)

      reply 200, page
    end

  end
end
