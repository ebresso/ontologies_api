require_relative '../test_case'

class TestOntologySubmissionsController < TestCase

  def self.before_suite
    _set_vars
    _create_user
    _create_onts
  end

  def self._set_vars
    @@acronym = "TST"
    @@name = "Test Ontology"
    @@test_file = File.expand_path("../../data/ontology_files/BRO_v3.1.owl", __FILE__)
    @@file_params = {
      name: @@name,
      hasOntologyLanguage: "OWL",
      administeredBy: "tim",
      "file" => Rack::Test::UploadedFile.new(@@test_file, ""),
      released: DateTime.now.to_s,
      contact: [{name: "test_name", email: "test@example.org"}]
    }
    @@status_uploaded = "UPLOADED"
    @@status_rdf = "RDF"
  end

  def self._create_user
    username = "tim"
    test_user = User.new(username: username, email: "#{username}@example.org", password: "password")
    test_user.save if test_user.valid?
    @@user = test_user.valid? ? test_user : User.find(username).first
  end

  def self._create_onts
    ont = Ontology.new(acronym: @@acronym, name: @@name, administeredBy: [@@user])
    ont.save
  end

  def test_submissions_for_given_ontology
    num_onts_created, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1)
    ontology = created_ont_acronyms.first
    get "/ontologies/#{ontology}/submissions"
    assert last_response.ok?

    submissions_goo = OntologySubmission.where(ontology: { acronym: ontology}).to_a

    submissions = MultiJson.load(last_response.body)
    assert submissions.length == submissions_goo.length
  end

  def test_create_new_submission_missing_file_and_pull_location
    post "/ontologies/#{@@acronym}/submissions", name: @@name, hasOntologyLanguage: "OWL"
    assert_equal(400, last_response.status, msg=get_errors(last_response))
    assert MultiJson.load(last_response.body)["errors"]
  end

  def test_create_new_submission_file
    post "/ontologies/#{@@acronym}/submissions", @@file_params
    assert_equal(201, last_response.status, msg=get_errors(last_response))
    sub = MultiJson.load(last_response.body)
    get "/ontologies/#{@@acronym}"
    ont = MultiJson.load(last_response.body)
    assert ont["acronym"].eql?(@@acronym)
    # Cleanup
    delete "/ontologies/#{@@acronym}/submissions/#{sub['submissionId']}"
    assert_equal(204, last_response.status, msg=get_errors(last_response))
  end

  def test_create_new_submission_and_parse
    post "/ontologies/#{@@acronym}/submissions", @@file_params
    assert_equal(201, last_response.status, msg=get_errors(last_response))
    sub = MultiJson.load(last_response.body)
    get "/ontologies/#{@@acronym}/submissions/#{sub['submissionId']}?include=all"
    ont = MultiJson.load(last_response.body)
    assert ont["ontology"]["acronym"].eql?(@@acronym)
    post "/ontologies/#{@@acronym}/submissions/#{sub['submissionId']}/parse"
    assert_equal(200, last_response.status, msg=get_errors(last_response))
    # Wait for the ontology parsing process to complete
    max = 25
    while (ont["submissionStatus"].length == 1 and ont["submissionStatus"].include?(@@status_uploaded) and max > 0)
      get "/ontologies/#{@@acronym}/submissions/#{sub['submissionId']}?include=all"
      assert_equal(200, last_response.status, msg=get_errors(last_response))
      ont = MultiJson.load(last_response.body)
      max = max - 1
      sleep(1.5)
    end
    assert max > 0
    assert ont["submissionStatus"].include?(@@status_rdf)
    # Try to get roots
    get "/ontologies/#{@@acronym}/classes/roots"
    assert_equal(200, last_response.status, msg=get_errors(last_response))
    roots = MultiJson.load(last_response.body)
    assert roots.length > 0
  end

  def test_create_new_ontology_submission
    post "/ontologies/#{@@acronym}/submissions", @@file_params
    assert_equal(201, last_response.status, msg=get_errors(last_response))
    # Cleanup
    sub = MultiJson.load(last_response.body)
    delete "/ontologies/#{@@acronym}/submissions/#{sub['submissionId']}"
    assert_equal(204, last_response.status, msg=get_errors(last_response))
  end

  def test_patch_ontology_submission
    num_onts_created, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1)
    ont = Ontology.find(created_ont_acronyms.first).include(submissions: [:submissionId, ontology: :acronym]).first
    assert(ont.submissions.length > 0)
    submission = ont.submissions[0]
    new_values = {description: "Testing new description changes"}
    patch "/ontologies/#{submission.ontology.acronym}/submissions/#{submission.submissionId}", MultiJson.dump(new_values), "CONTENT_TYPE" => "application/json"
    assert_equal(204, last_response.status, msg=get_errors(last_response))
    get "/ontologies/#{submission.ontology.acronym}/submissions/#{submission.submissionId}"
    submission = MultiJson.load(last_response.body)
    assert submission["description"].eql?("Testing new description changes")
  end

  def test_delete_ontology_submission
    num_onts_created, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1, random_submission_count: false, submission_count: 5)
    acronym = created_ont_acronyms.first
    submission_to_delete = (1..5).to_a.shuffle.first
    delete "/ontologies/#{acronym}/submissions/#{submission_to_delete}"
    assert_equal(204, last_response.status, msg=get_errors(last_response))

    get "/ontologies/#{acronym}/submissions/#{submission_to_delete}"
    assert_equal(404, last_response.status, msg=get_errors(last_response))
  end

  def test_download_submission
    num_onts_created, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true)
    assert_equal(1, num_onts_created, msg="Failed to create 1 ontology?")
    assert_equal(1, onts.length, msg="Failed to create 1 ontology?")
    ont = onts.first
    assert_instance_of(Ontology, ont, msg="ont is not a #{Ontology.class}")
    assert_equal(1, ont.submissions.length, msg="Failed to create 1 ontology submission?")
    sub = ont.submissions.first
    assert_instance_of(OntologySubmission, sub, msg="sub is not a #{OntologySubmission.class}")
    # Clear restrictions on downloads
    LinkedData::OntologiesAPI.settings.restrict_download = []
    # Download the specific submission
    get "/ontologies/#{sub.ontology.acronym}/submissions/#{sub.submissionId}/download"
    assert_equal(200, last_response.status, msg='failed download for specific submission : ' + get_errors(last_response))
    # Add restriction on download
    acronym = created_ont_acronyms.first
    LinkedData::OntologiesAPI.settings.restrict_download = [acronym]
    # Try download
    get "/ontologies/#{sub.ontology.acronym}/submissions/#{sub.submissionId}/download"
    # download should fail with a 403 status
    assert_equal(403, last_response.status, msg='failed to restrict download for ontology : ' + get_errors(last_response))
    # Clear restrictions on downloads
    LinkedData::OntologiesAPI.settings.restrict_download = []
    # see also test_ontologies_controller::test_download_ontology
  end

  #
  # NOTE: download restrictions are tested in the download test above.
  #
  #def test_download_restricted_submission
  #  num_onts_created, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true)
  #  assert_equal(1, num_onts_created, msg="Failed to create 1 ontology?")
  #  assert_equal(1, onts.length, msg="Failed to create 1 ontology?")
  #  ont = onts.first
  #  assert_instance_of(Ontology, ont, msg="ont is not a #{Ontology.class}")
  #  assert_equal(1, ont.submissions.length, msg="Failed to create 1 ontology submission?")
  #  sub = ont.submissions.first
  #  assert_instance_of(OntologySubmission, sub, msg="sub is not a #{OntologySubmission.class}")
  #  # Add restriction on download
  #  acronym = created_ont_acronyms.first
  #  LinkedData::OntologiesAPI.settings.restrict_download = [acronym]
  #  # Try download
  #  get "/ontologies/#{sub.ontology.acronym}/submissions/#{sub.submissionId}/download"
  #  # download should fail with a 403 status
  #  assert_equal(403, last_response.status, msg='failed to restrict download for ontology : ' + get_errors(last_response))
  #  # Clear restrictions on downloads
  #  LinkedData::OntologiesAPI.settings.restrict_download = []
  #  # see also test_ontologies_controller::test_download_restricted_ontology
  #end

  #
  # TODO: Test the submission diff file download
  #
  #def test_download_submission_diff
  #  num_onts_created, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true)
  #  assert_equal(1, num_onts_created, msg="Failed to create 1 ontology?")
  #  assert_equal(1, onts.length, msg="Failed to create 1 ontology?")
  #  ont = onts.first
  #  assert_instance_of(Ontology, ont, msg="ont is not a #{Ontology.class}")
  #  assert_equal(1, ont.submissions.length, msg="Failed to create 1 ontology submission?")
  #  sub = ont.submissions.first
  #  assert_instance_of(OntologySubmission, sub, msg="sub is not a #{OntologySubmission.class}")
  #  # Clear restrictions on downloads
  #  LinkedData::OntologiesAPI.settings.restrict_download = []
  #  # Download the specific submission
  #  get "/ontologies/#{sub.ontology.acronym}/submissions/#{sub.submissionId}/download"
  #  assert_equal(200, last_response.status, msg='failed download for specific submission : ' + get_errors(last_response))
  #  # Add restriction on download
  #  acronym = created_ont_acronyms.first
  #  LinkedData::OntologiesAPI.settings.restrict_download = [acronym]
  #  # Try download
  #  get "/ontologies/#{sub.ontology.acronym}/submissions/#{sub.submissionId}/download"
  #  # download should fail with a 403 status
  #  assert_equal(403, last_response.status, msg='failed to restrict download for ontology : ' + get_errors(last_response))
  #  # Clear restrictions on downloads
  #  LinkedData::OntologiesAPI.settings.restrict_download = []
  #  # see also test_ontologies_controller::test_download_ontology
  #end

  def test_ontology_submission_properties
    # not implemented yet
  end


end
