module StripeHelper

  TxApi = TransactionService::API::Api

  module_function

  def community_ready_for_payments?(community_id)
    return false unless stripe_feature_enabled?(community_id)
    stripe_active?(community_id) &&
      Maybe(TxApi.settings.get(community_id: community_id, payment_gateway: :stripe, payment_process: :preauthorize))
      .map {|res| res[:success] ? res[:data] : nil}
      .select {|set| set[:commission_from_seller] && set[:minimum_price_cents]}
      .map {|_| true}
      .or_else(false)
  end

  def stripe_active?(community_id)
    return false unless stripe_feature_enabled?(community_id)
    active_settings = Maybe(TxApi.settings.get(community_id: community_id, payment_gateway: :stripe, payment_process: :preauthorize))
      .select { |result| result[:success] }
      .map { |result| result[:data] }
      .or_else(nil)

    return active_settings && active_settings[:active] && active_settings[:api_verified]
  end

  def stripe_provisioned?(community_id)
    return false unless stripe_feature_enabled?(community_id)
    settings = Maybe(TxApi.settings.get(
                      community_id: community_id,
                      payment_gateway: :stripe,
                      payment_process: :preauthorize))
      .select { |result| result[:success] }
      .map { |result| result[:data] }
      .or_else(nil)

    return !!settings
  end

  def user_and_community_ready_for_payments?(person_id, community_id)
    stripe_active?(community_id) && user_stripe_active?(community_id, person_id)
  end

  def user_stripe_active?(community_id, person_id)
    account = StripeService::API::Api.accounts.get(community_id: community_id, person_id: person_id).data
    account && account[:stripe_seller_id].present? && account[:stripe_bank_id].present?
  end

  def publishable_key(community_id)
    return nil unless StripeHelper.stripe_active?(community_id)
    payment_settings = TransactionService::API::Api.settings.get_active_by_gateway(community_id: community_id, payment_gateway: :stripe).maybe.get
    payment_settings[:api_publishable_key]
  end

  # Check if the user has open listings in the community but has not
  # finished connecting his paypal account.
  def open_listings_with_missing_payment_info?(user_id, community_id)
    stripe_active?(community_id) &&
      !user_and_community_ready_for_payments?(user_id, community_id) &&
      PaypalHelper.open_listings_with_payment_process?(community_id, user_id)
  end

  # We are not using FeatureFlagHelper.feature_enabled?(:stripe) here,
  # the reason is that method Community#payments_in_use? uses MarketplaceService::Community::Query.payment_type which calls StripeHelper.stripe_active?
  # and it can be invoked in context where FeatureFlagHelper is not initialized, like from PersonMailer
  def stripe_feature_enabled?(community_id)
    features = FeatureFlagService::API::Api.features.get_for_community(community_id: community_id).maybe[:features].or_else(Set.new)
    features.include?(:stripe)
  end

  def stripe_country_spec(country)
    STRIPE_COUNTRY_SPECS["data"].detect{|spec| spec["id"] == country }
  end

  def stripe_bank_currencies(country)
    country_spec = stripe_country_spec(country)
    return [] unless country_spec
    bank_currencies = country_spec["supported_bank_account_currencies"]
    bank_currencies.keys.select{|currency| bank_currencies[currency].include?(country) }
  end

  def stripe_allows_country_and_currency?(country, currency)
    stripe_bank_currencies(country).include?(currency.downcase)
  end
end
