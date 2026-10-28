class LawyerOnboarding
  class InvalidProfile < StandardError
    attr_reader :details
    def initialize(profile)
      @details = profile.errors.to_hash
      super("Confira os dados do perfil profissional.")
    end
  end
  class AlreadyOnboarded < StandardError; end
  class Unauthenticated < StandardError; end

  def self.call(token:, input:)
    profile = OnboardingProfile.new(input)
    raise InvalidProfile, profile unless profile.valid?

    DatabaseContext.with_session(token) do
      context = IdentityStore.context(token)
      raise Unauthenticated unless context
      # Locks the identity row, so concurrent requests cannot create two tenants.
      claim = IdentityStore.call("claim_tenant", IdentityStore.digest(token))
      raise Unauthenticated unless claim
      raise AlreadyOnboarded unless claim.fetch("claimed")
      tenant = Tenant.create!(id: claim.fetch("tenant_id"))
      lawyer = Lawyer.create!(tenant: tenant, full_name: profile.full_name, office_name: profile.office_name)
      profile.registrations.each { |registration| OabRegistration.create!(registration.merge(tenant: tenant, lawyer: lawyer)) }
      # Fire the actual deferred constraint while this profile's RLS context is
      # still active, even when the caller owns the outer transaction. Only this
      # named trigger changes timing; deferred tenant FKs keep their own timing.
      connection = ApplicationRecord.connection
      connection.execute("SET CONSTRAINTS public.lawyer_requires_primary_oab IMMEDIATE")
      connection.execute("SET CONSTRAINTS public.lawyer_requires_primary_oab DEFERRED")
      lawyer
    end
  end
end
