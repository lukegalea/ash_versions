import Config

config :ash, default_string_length_count: :codepoints

if config_env() == :test do
  config :ash_versions, ash_domains: [AshVersions.Test.Domain]
  config :ash, disable_async?: true
  config :logger, level: :warning
end
