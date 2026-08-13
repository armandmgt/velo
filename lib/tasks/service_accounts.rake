namespace :service_accounts do
  desc "Create a service account and print a bearer token for API access (usage: bin/rails service_accounts:create[name])"
  task :create, [ :name ] => :environment do |_task, args|
    name = (args[:name] || "routine").to_s.strip

    session = Session.create!(service_account: true, user_agent: "service-account:#{name}")
    token = session.generate_token_for(:service_account_api)

    puts "Service account session created (id=#{session.id}, name=#{name})"
    puts "Bearer token (store this in the routine instructions; it is not shown again):"
    puts token
    puts "Revoke later with: Session.find(#{session.id}).destroy"
  end
end
