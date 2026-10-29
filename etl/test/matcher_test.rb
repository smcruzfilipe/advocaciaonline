# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/processador/matcher"

class MatcherTest < Minitest::Test
  LAWYER_NAME = "Guilherme Curcelli Guimarães"
  CNJ = "00012345620248010001"
  MASKED_CNJ = "0001234-56.2024.8.01.0001"
  UFS = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO].freeze

  # These OABs are controlled fixtures, not claims about the named lawyer's registrations.
  def test_lawyer_name_ignores_case_accents_and_unicode_whitespace
    publication = lawyer_publication(name: "\u00a0GUILHERME\t CURCELLI\nGUIMARAES  ")

    assert Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria, publication: publication)
  end

  def test_lawyer_name_accepts_canonically_decomposed_diacritics
    publication = lawyer_publication(name: "Guilherme Curcelli Guimara\u0303es")

    assert Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria, publication: publication)
  end

  def test_lawyer_name_normalizes_the_snapshot_too
    criteria = { "name" => " \tGUILHERME  CURCELLI\nGUIMARAES ", "oabs" => [] }

    assert Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria,
      publication: lawyer_publication(name: LAWYER_NAME))
  end

  def test_lawyer_name_rejects_punctuation_changes_abbreviations_and_substrings
    ["Guilherme, Curcelli Guimarães", "Guilherme-Curcelli Guimarães", "Guilherme C. Guimarães",
     "Guilherme Curcelli", "Guilherme Curcelli Guimarães Filho", "Texto #{LAWYER_NAME} texto"].each do |name|
      refute Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria,
        publication: lawyer_publication(name: name)), name
    end
  end

  def test_lawyer_name_does_not_require_or_disambiguate_an_oab
    publication = lawyer_publication(name: LAWYER_NAME, number: "Outra inscrição", uf: "SP")
    publication["destinatarioadvogados"].first["advogado"]["id"] = 999
    publication["destinatarioadvogados"].first["polo"] = "P"

    assert Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria, publication: publication)
  end

  def test_lawyer_matches_any_nested_recipient_not_just_the_first
    publication = { "destinatarioadvogados" => [
      { "advogado" => { "nome" => "Outra pessoa" } },
      { "advogado" => { "nome" => LAWYER_NAME } }
    ] }

    assert Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria, publication: publication)
  end

  def test_primary_oab_matches_without_a_matching_name
    publication = lawyer_publication(name: "Nome diferente", number: "001234-A", uf: "AC")

    assert Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria, publication: publication)
  end

  def test_secondary_oab_matches_without_a_name_and_duplicate_pairs_do_not_change_the_result
    criteria = lawyer_criteria
    criteria["oabs"] << criteria["oabs"].last.dup
    publication = lawyer_publication(number: "00a. A-b", uf: "DF")

    assert_equal true, Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria, publication: publication)
  end

  def test_oab_trims_only_outer_whitespace_and_normalizes_uf_on_both_sides
    criteria = { "oabs" => [{ "number" => "\u00a0 00a. A-b\t", "uf" => " df\n" }] }
    publication = lawyer_publication(number: "\n00a. A-b\u00a0", uf: "\tDf ")

    assert Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria, publication: publication)
  end

  def test_oab_preserves_leading_zeroes_suffix_punctuation_internal_spaces_and_case
    criteria = { "oabs" => [{ "number" => "00a. A-b", "uf" => "DF" }] }
    ["0a. A-b", "00a. A", "00a A-b", "00a.A-b", "00a.  A-b", "00A. A-b", "00a. A-B"].each do |number|
      refute Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria,
        publication: lawyer_publication(number: number, uf: "DF")), number
    end
  end

  def test_oab_leading_zeroes_and_suffix_are_not_discarded
    ["1234-A", "001234", "001234-a"].each do |number|
      refute Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria,
        publication: lawyer_publication(number: number, uf: "AC")), number
    end
  end

  def test_oab_requires_both_fields_of_the_same_pair
    criteria = { "oabs" => [
      { "number" => "001234-A", "uf" => "AC" },
      { "number" => "009999", "uf" => "SP" }
    ] }

    refute Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria,
      publication: lawyer_publication(number: "001234-A", uf: "SP"))
  end

  def test_oab_does_not_combine_fields_from_different_lawyers
    publication = { "destinatarioadvogados" => [
      { "advogado" => { "numero_oab" => "001234-A", "uf_oab" => "SP" } },
      { "advogado" => { "numero_oab" => "009999", "uf_oab" => "AC" } }
    ] }

    refute Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria, publication: publication)
  end

  def test_oab_accepts_all_27_brazilian_ufs_including_df
    UFS.each do |uf|
      criteria = { "oabs" => [{ "number" => "001234-A", "uf" => uf.downcase }] }

      assert Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria,
        publication: lawyer_publication(number: "001234-A", uf: " #{uf} ")), uf
    end
  end

  def test_oab_rejects_invalid_ufs_even_when_the_tokens_are_identical
    [nil, "", "  ", "XX", "BR", "São Paulo", "S P", 12, []].each do |uf|
      criteria = { "oabs" => [{ "number" => "001234-A", "uf" => uf }] }

      refute Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria,
        publication: lawyer_publication(number: "001234-A", uf: uf)), uf.inspect
    end
  end

  def test_oab_rejects_missing_blank_and_nontextual_numbers_on_either_side
    [nil, "", " \t\n\u00a0", 1234, 1234.0, [], {}].each do |number|
      criteria = { "oabs" => [{ "number" => number, "uf" => "AC" }] }
      publication = lawyer_publication(number: number, uf: "AC")

      refute Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria, publication: publication), number.inspect
      refute Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria, publication: publication), number.inspect
      refute Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria,
        publication: lawyer_publication(number: "001234-A", uf: "AC")), number.inspect
    end
  end

  def test_invalid_oab_does_not_disable_the_alternative_match_by_name
    criteria = { "name" => LAWYER_NAME, "oabs" => [{ "number" => 1234, "uf" => "XX" }] }
    publication = lawyer_publication(name: LAWYER_NAME, number: 1234, uf: "XX")

    assert Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria, publication: publication)
  end

  def test_invalid_name_does_not_disable_the_alternative_match_by_oab
    [nil, "", " \t\n\u00a0", 123, [], {}].each do |name|
      criteria = lawyer_criteria.merge("name" => name)

      assert Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria,
        publication: lawyer_publication(name: name, number: "001234-A", uf: "AC")), name.inspect
    end
  end

  def test_lawyer_does_not_match_empty_or_nontextual_names
    [nil, "", " \t\n\u00a0", 123, [], {}, "\u0301"].each do |name|
      criteria = { "name" => name, "oabs" => [] }

      refute Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria,
        publication: lawyer_publication(name: name)), name.inspect
      refute Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria,
        publication: lawyer_publication(name: name)), name.inspect
    end
  end

  def test_lawyer_only_uses_the_documented_nested_lawyer_fields
    publication = { "nome" => LAWYER_NAME, "texto" => LAWYER_NAME,
      "advogado" => { "nome" => LAWYER_NAME }, "destinatarios" => [{ "nome" => LAWYER_NAME }],
      "destinatarioadvogados" => [{ "nome" => LAWYER_NAME, "numero_oab" => "001234-A", "uf_oab" => "AC" }] }

    refute Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria, publication: publication)
  end

  def test_party_name_ignores_case_diacritics_and_whitespace
    criteria = { "name" => "  JOSE\t da  Silva\n" }
    publication = { "destinatarios" => [{ "nome" => "\u00a0José  da\nSilva\t" }] }

    assert Processador::Matcher.match?(entity_type: "party", criteria: criteria, publication: publication)
  end

  def test_party_preserves_matching_punctuation_without_compatibility_transliteration
    criteria = { "name" => "José, D’Ávila-Silva" }
    assert Processador::Matcher.match?(entity_type: "party", criteria: criteria,
      publication: { "destinatarios" => [{ "nome" => "JOSE, D’AVILA-SILVA" }] })

    ["José D’Ávila-Silva", "José, D'Ávila-Silva", "José, D’Ávila Silva", "José, D’Ávila−Silva"].each do |name|
      refute Processador::Matcher.match?(entity_type: "party", criteria: criteria,
        publication: { "destinatarios" => [{ "nome" => name }] }), name
    end
  end

  def test_party_rejects_punctuation_changes_abbreviations_and_partial_names
    ["José, da Silva", "José-da-Silva", "José da Silva Filho", "José Silva", "J. da Silva", "José"].each do |name|
      refute Processador::Matcher.match?(entity_type: "party", criteria: { "name" => "José da Silva" },
        publication: { "destinatarios" => [{ "nome" => name }] }), name
    end
  end

  def test_party_does_not_disambiguate_homonyms_by_id_or_polo
    %w[A P].each do |polo|
      publication = { "destinatarios" => [
        { "id" => 1, "nome" => "Outra parte", "polo" => "A" },
        { "id" => 999, "nome" => "José da Silva", "polo" => polo }
      ] }

      assert Processador::Matcher.match?(entity_type: "party", criteria: { "name" => "José da Silva" }, publication: publication)
    end
  end

  def test_party_does_not_use_lawyer_names_or_publication_text
    publication = lawyer_publication(name: "José da Silva")
    publication["nome"] = "José da Silva"
    publication["texto"] = "José da Silva"

    refute Processador::Matcher.match?(entity_type: "party", criteria: { "name" => "José da Silva" }, publication: publication)
  end

  def test_party_does_not_match_missing_blank_or_nontextual_names
    [nil, "", "\t\n \u00a0", 123, [], {}, "\u0301"].each do |name|
      refute Processador::Matcher.match?(entity_type: "party", criteria: { "name" => name },
        publication: { "destinatarios" => [{ "nome" => name }] }), name.inspect
      refute Processador::Matcher.match?(entity_type: "party", criteria: { "name" => "José da Silva" },
        publication: { "destinatarios" => [{ "nome" => name }] }), name.inspect
    end
  end

  def test_process_matches_masked_and_unmasked_forms_in_both_directions
    [CNJ, MASKED_CNJ].product([CNJ, MASKED_CNJ]).each do |criteria_number, source_number|
      assert Processador::Matcher.match?(entity_type: "process", criteria: { "number" => criteria_number },
        publication: { "numero_processo" => source_number }), [criteria_number, source_number].inspect
    end
  end

  def test_process_preserves_leading_zeroes_and_compares_all_20_digits
    ["10012345620248010001", "00012345620248010002", "00012345620248020001"].each do |number|
      refute Processador::Matcher.match?(entity_type: "process", criteria: { "number" => CNJ },
        publication: { "numero_processo" => number }), number
    end
  end

  def test_process_rejects_malformed_numbers_on_both_sides
    malformed = [nil, "", CNJ.to_i, 1.0, [], {}, CNJ[1..], "#{CNJ}0", "0001234A620248010001",
      " #{CNJ}", "#{CNJ} ", "#{CNJ}\n", "#{CNJ}\x00", "#{MASKED_CNJ}\n", " #{MASKED_CNJ}",
      "0001234.56.2024.8.01.0001", "0001234-56-2024.8.01.0001", "0001234-56.2024.8.010001",
      "000123456.2024.8.01.0001", "0001234--56.2024.8.01.0001", "0001234/56.2024.8.01.0001",
      "0001234–56.2024.8.01.0001", "0001234-56．2024.8.01.0001", "0001234-56.2024.8.01.0001.",
      CNJ.tr("0-9", "０-９"), CNJ.tr("0-9", "٠-٩")]

    malformed.each do |number|
      refute Processador::Matcher.match?(entity_type: "process", criteria: { "number" => CNJ },
        publication: { "numero_processo" => number }), number.inspect
      refute Processador::Matcher.match?(entity_type: "process", criteria: { "number" => number },
        publication: { "numero_processo" => CNJ }), number.inspect
      refute Processador::Matcher.match?(entity_type: "process", criteria: { "number" => number },
        publication: { "numero_processo" => number }), number.inspect
    end
  end

  def test_process_only_uses_numero_processo_not_text_or_other_number_fields
    publication = { "texto" => CNJ, "number" => CNJ, "numeroProcesso" => CNJ }

    refute Processador::Matcher.match?(entity_type: "process", criteria: { "number" => CNJ }, publication: publication)
  end

  def test_malformed_nested_entries_do_not_hide_a_later_valid_match
    publication = { "destinatarioadvogados" => [nil, false, 1, "advogado", [], {},
      { "advogado" => [] }, { "advogado" => false }, { "advogado" => { "nome" => LAWYER_NAME } }],
      "destinatarios" => [nil, false, 1, "parte", [], {}, { "nome" => "José da Silva" }] }
    criteria = { "oabs" => [nil, false, 1, "OAB", [], {}, { "number" => "001234-A", "uf" => "AC" }] }

    assert Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria, publication: publication)
    assert Processador::Matcher.match?(entity_type: "party", criteria: { "name" => "José da Silva" }, publication: publication)
    assert Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria,
      publication: lawyer_publication(number: "001234-A", uf: "AC"))
  end

  def test_missing_or_nonarray_recipients_do_not_match
    [nil, false, 1, "texto", {}, { "nome" => LAWYER_NAME }].each do |value|
      publication = { "destinatarioadvogados" => value, "destinatarios" => value }

      refute Processador::Matcher.match?(entity_type: "lawyer", criteria: lawyer_criteria, publication: publication), value.inspect
      refute Processador::Matcher.match?(entity_type: "party", criteria: { "name" => LAWYER_NAME }, publication: publication), value.inspect
    end
  end

  def test_nonarray_oabs_do_not_create_an_oab_match_or_prevent_a_name_match
    [nil, false, 1, "001234-A", { "number" => "001234-A", "uf" => "AC" }].each do |oabs|
      criteria = { "name" => LAWYER_NAME, "oabs" => oabs }

      refute Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria,
        publication: lawyer_publication(number: "001234-A", uf: "AC")), oabs.inspect
      assert Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria,
        publication: lawyer_publication(name: LAWYER_NAME)), oabs.inspect
    end
  end

  def test_unknown_entity_and_malformed_roots_return_false
    [nil, "", "advogado", :lawyer, "LAWYER"].each do |entity_type|
      assert_equal false, Processador::Matcher.match?(entity_type: entity_type,
        criteria: lawyer_criteria, publication: lawyer_publication(name: LAWYER_NAME))
    end
    [nil, false, 1, "texto", []].each do |value|
      %w[lawyer party process].each do |entity_type|
        assert_equal false, Processador::Matcher.match?(entity_type: entity_type, criteria: value, publication: {})
        assert_equal false, Processador::Matcher.match?(entity_type: entity_type, criteria: {}, publication: value)
      end
    end
  end

  def test_matching_does_not_mutate_the_frozen_job_snapshot_or_publication
    criteria = deep_freeze(lawyer_criteria)
    publication = deep_freeze(lawyer_publication(name: " GUILHERME  CURCELLI GUIMARAES ", number: " 001234-A ", uf: " ac "))

    assert Processador::Matcher.match?(entity_type: "lawyer", criteria: criteria, publication: publication)
    assert_equal LAWYER_NAME, criteria.fetch("name")
    assert_equal " GUILHERME  CURCELLI GUIMARAES ", publication.fetch("destinatarioadvogados").first.fetch("advogado").fetch("nome")
    assert_equal " 001234-A ", publication.fetch("destinatarioadvogados").first.fetch("advogado").fetch("numero_oab")
    assert_equal " ac ", publication.fetch("destinatarioadvogados").first.fetch("advogado").fetch("uf_oab")
  end

  private

  def lawyer_criteria
    { "name" => LAWYER_NAME, "oabs" => [
      { "number" => "001234-A", "uf" => "AC" },
      { "number" => "00a. A-b", "uf" => "DF" }
    ] }
  end

  def lawyer_publication(name: nil, number: nil, uf: nil)
    { "destinatarioadvogados" => [{ "advogado" => { "nome" => name, "numero_oab" => number, "uf_oab" => uf } }] }
  end

  def deep_freeze(value)
    case value
    when Hash then value.each { |key, child| deep_freeze(key); deep_freeze(child) }
    when Array then value.each { |child| deep_freeze(child) }
    end
    value.freeze
  end
end
