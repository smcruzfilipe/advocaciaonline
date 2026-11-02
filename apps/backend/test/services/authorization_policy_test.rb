require "test_helper"

class AuthorizationPolicyTest < ActiveSupport::TestCase
  GROUP_OPERATIONS = %w[consultar_monitoramentos consultar_comunicacoes consultar_dashboard
    cadastrar_monitoramento editar_monitoramento desativar_monitoramento consultar_agenda
    cadastrar_compromisso remarcar_compromisso cancelar_compromisso].freeze
  OWNER_ONLY_OPERATIONS = %w[convidar_usuario consultar_usuarios alterar_validade_credencial
    revogar_credencial renovar_credencial consultar_grupos administrar_grupos consultar_escrevente
    configurar_agenda].freeze

  test "implements the approved monitoring communications and dashboard matrix" do
    cases = [
      [[], [true, true, true, true, false, false, false]],
      [[[rule("consultar_comunicacoes", court: "TJSP")]],
        [false, true, false, false, false, false, false]],
      [[[rule("consultar_comunicacoes", court: "TJSP"), rule("consultar_comunicacoes", court: "TJRJ"),
          rule("consultar_dashboard", effect: "deny")]],
        [false, true, true, false, false, false, false]],
      [[[rule("consultar_comunicacoes", court: "TJSP")],
         [rule("consultar_comunicacoes", court: "TJRJ"), rule("consultar_comunicacoes", effect: "deny", court: "TJRJ")]],
        [false, true, false, false, false, false, false]],
      [[[rule("cadastrar_monitoramento")]], [false, false, false, false, true, false, false]],
      [[[rule("cadastrar_monitoramento")], [rule("cadastrar_monitoramento", effect: "deny")]],
        [false, false, false, false, false, false, false]]
    ]
    decisions = [["consultar_monitoramentos", nil], ["consultar_comunicacoes", "TJSP"],
      ["consultar_comunicacoes", "TJRJ"], ["consultar_dashboard", nil],
      ["cadastrar_monitoramento", nil], ["editar_monitoramento", nil], ["desativar_monitoramento", nil]]

    cases.each do |groups, expected|
      decisions.each_with_index do |(operation, court), index|
        assert_equal expected[index], AuthorizationPolicy.allowed?(owner: false, groups: groups,
          operation: operation, court: court), "#{groups.inspect}: #{operation} #{court}"
      end
    end
  end

  test "owner has every catalogued operation independently of group denials" do
    (GROUP_OPERATIONS + OWNER_ONLY_OPERATIONS).each do |operation|
      groups = [[rule(operation, effect: "deny")]]
      court = operation == "consultar_comunicacoes" ? "TJSP" : nil
      assert AuthorizationPolicy.allowed?(owner: true, groups: groups, operation: operation, court: court), operation
    end
  end

  test "unknown operations are denied for owner and team even when a rule grants them" do
    ["excluir_usuario", "consultar_disponibilidade", "consultar_tudo", "*", "", nil,
      :consultar_monitoramentos, "CONSULTAR_MONITORAMENTOS"].each do |operation|
      [true, false].each do |owner|
        assert_not AuthorizationPolicy.allowed?(owner: owner, groups: [], operation: operation)
        assert_not AuthorizationPolicy.allowed?(owner: owner, groups: [[rule(operation)]], operation: operation)
      end
    end
  end

  test "each team operation needs its own grant when groups exist" do
    GROUP_OPERATIONS.each do |operation|
      groups = [[rule(operation, court: operation == "consultar_comunicacoes" ? "TJSP" : nil)]]
      GROUP_OPERATIONS.each do |requested|
        assert_equal operation == requested,
          AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: requested,
            court: requested == "consultar_comunicacoes" ? "TJSP" : nil), "#{operation} does not imply #{requested}"
      end
    end
  end

  test "administration agenda configuration and Escrevente cannot be delegated" do
    OWNER_ONLY_OPERATIONS.each do |operation|
      assert_not AuthorizationPolicy.allowed?(owner: false, groups: [], operation: operation)
      assert_not AuthorizationPolicy.allowed?(owner: false, groups: [[rule(operation)]], operation: operation)
    end
  end

  test "team without groups has no agenda access" do
    %w[consultar_agenda cadastrar_compromisso remarcar_compromisso cancelar_compromisso].each do |operation|
      assert_not AuthorizationPolicy.allowed?(owner: false, groups: [], operation: operation)
    end
  end

  test "an empty group suppresses the default wide reads" do
    GROUP_OPERATIONS.each do |operation|
      assert_not AuthorizationPolicy.allowed?(owner: false, groups: [[]], operation: operation, court: "TJSP"), operation
    end
  end

  test "grants accumulate across groups without broadening operation or court" do
    groups = [[rule("consultar_comunicacoes", court: "TJSP")],
      [rule("consultar_comunicacoes", court: "TJRJ"), rule("consultar_dashboard")],
      [rule("consultar_monitoramentos")]]

    assert AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_monitoramentos")
    assert AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_dashboard")
    %w[TJSP TJRJ].each do |court|
      assert AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_comunicacoes", court: court)
    end
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_comunicacoes", court: "TRF1")
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "cadastrar_monitoramento")
  end

  test "dashboard permission and communications permissions remain independent" do
    groups = [[rule("consultar_dashboard")]]
    assert AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_dashboard")
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_comunicacoes", court: "TJSP")

    groups = [[rule("consultar_dashboard", effect: "deny"), rule("consultar_comunicacoes", court: "TJSP")]]
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_dashboard")
    assert AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_comunicacoes", court: "TJSP")
  end

  test "a matching deny prevails regardless of group or rule order" do
    GROUP_OPERATIONS.each do |operation|
      court = operation == "consultar_comunicacoes" ? "TJSP" : nil
      allow = rule(operation, court: court)
      deny = rule(operation, effect: "deny", court: court)
      [[[allow], [deny]], [[deny], [allow]], [[allow, deny]], [[deny, allow]]].each do |groups|
        assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: operation, court: court), operation
      end
    end
  end

  test "a court specific denial overrides an all courts grant only for that court" do
    groups = [[rule("consultar_comunicacoes")], [rule("consultar_comunicacoes", effect: "deny", court: "TJRJ")]]
    [groups, groups.reverse].each do |ordered|
      assert_not AuthorizationPolicy.allowed?(owner: false, groups: ordered, operation: "consultar_comunicacoes", court: "TJRJ")
      %w[TJSP TRF1].each do |court|
        assert AuthorizationPolicy.allowed?(owner: false, groups: ordered, operation: "consultar_comunicacoes", court: court)
      end
    end
  end

  test "an all courts denial overrides a court specific grant" do
    groups = [[rule("consultar_comunicacoes", court: "TJSP")], [rule("consultar_comunicacoes", effect: "deny")]]
    [groups, groups.reverse].each do |ordered|
      assert_not AuthorizationPolicy.allowed?(owner: false, groups: ordered, operation: "consultar_comunicacoes", court: "TJSP")
      assert_not AuthorizationPolicy.allowed?(owner: false, groups: ordered, operation: "consultar_comunicacoes", court: "TJRJ")
    end
  end

  test "denying one operation does not revoke another operation in the same scope" do
    groups = [[rule("cadastrar_compromisso", effect: "deny"), rule("remarcar_compromisso"),
      rule("consultar_monitoramentos", effect: "deny"), rule("consultar_dashboard")]]

    assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "cadastrar_compromisso")
    assert AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "remarcar_compromisso")
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_monitoramentos")
    assert AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_dashboard")
  end

  test "communications always requires an explicit nonblank court even for owner or wildcard grants" do
    [true, false].each do |owner|
      [[], [[rule("consultar_comunicacoes")]]].each do |groups|
        assert_not AuthorizationPolicy.allowed?(owner: owner, groups: groups, operation: "consultar_comunicacoes")
        [nil, "", " \t\n", :TJSP, 1, []].each do |court|
          assert_not AuthorizationPolicy.allowed?(owner: owner, groups: groups, operation: "consultar_comunicacoes", court: court)
        end
      end
    end
  end

  test "court matching is exact without inferring or normalizing another tribunal" do
    groups = [[rule("consultar_comunicacoes", court: "TJSP")]]
    ["tjsp", " TJSP ", "TJRJ"].each do |court|
      assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_comunicacoes", court: court)
    end
  end

  test "removing the last group restores only default reads and decisions are not memoized" do
    groups = [[rule("consultar_comunicacoes", effect: "deny", court: "TJSP")]]
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_comunicacoes", court: "TJSP")
    groups.clear
    assert AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_comunicacoes", court: "TJSP")
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "cadastrar_monitoramento")
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_agenda")
    groups << [rule("consultar_dashboard", effect: "deny")]
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_dashboard")
  end

  test "malformed groups and rules fail closed rather than becoming the no group default" do
    malformed = [nil, {}, "[]", [nil], [{}], ["group"], [[nil]], [[[]]],
      [[rule("consultar_dashboard").except("court")]],
      [[{ operation: "consultar_dashboard", effect: "allow", court: nil }]],
      [[rule("consultar_dashboard").merge(:court => nil)]],
      [[rule("consultar_dashboard", effect: "ALLOW")]],
      [[rule("consultar_dashboard", effect: nil)]],
      [[rule("unknown")]],
      [[rule("consultar_dashboard", court: "TJSP")]],
      [[rule("consultar_comunicacoes", court: "")]],
      [[rule("consultar_comunicacoes", court: " \t")]],
      [[rule("consultar_comunicacoes", court: :TJSP)]]]

    malformed.each do |groups|
      [true, false].each do |owner|
        assert_not AuthorizationPolicy.allowed?(owner: owner, groups: groups, operation: "consultar_dashboard"), groups.inspect
      end
    end
  end

  test "invalid rules cannot be ignored alongside valid grants regardless of their order" do
    valid = rule("consultar_dashboard")
    invalid = rule("consultar_comunicacoes").except("court")
    [[[valid], [invalid]], [[invalid], [valid]], [[valid, invalid]], [[invalid, valid]]].each do |groups|
      assert_not AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_dashboard")
    end
  end

  test "owner must be an explicit boolean from the authenticated context" do
    [nil, "true", "false", 1, {}].each do |owner|
      assert_not AuthorizationPolicy.allowed?(owner: owner, groups: [], operation: "consultar_dashboard")
      assert_not AuthorizationPolicy.allowed?(owner: owner, groups: [], operation: "administrar_grupos")
    end
  end

  test "policy reads frozen group data without modifying it" do
    groups = [[rule("consultar_comunicacoes", court: "TJSP").freeze].freeze].freeze
    assert AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: "consultar_comunicacoes", court: "TJSP")
    assert_equal [[{ "operation" => "consultar_comunicacoes", "effect" => "allow", "court" => "TJSP" }]], groups
  end

  private

  def rule(operation, effect: "allow", court: nil)
    { "operation" => operation, "effect" => effect, "court" => court }
  end
end
