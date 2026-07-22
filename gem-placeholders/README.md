# Placeholder gems — reserving the Ruby CDK names

Reserves the eight gem names the AWS CDK Ruby bindings use
([aws/aws-cdk-rfcs#939](https://github.com/aws/aws-cdk-rfcs/pull/939), *Gem
name governance*) before a squatter does. RubyGems has no reservation
mechanism; a claimed name with a documented transfer commitment is the only
protection that exists.

The placeholders are deliberately shaped so this is a signpost, not a squat:
prerelease-versioned (`0.0.0.pre.reserved.1` — Bundler and `gem install`
never pick prereleases by default), authored as Omar (not AWS), and every
README/require-stub points at the RFC and the working preview channel. The
RFC documents the standing commitment to transfer ownership to AWS
(`gem owner --add`) on request.

## One-time account setup (no rubygems.org account yet)

1. **Create the account**: <https://rubygems.org/sign_up> — suggest
   `omar@omarqureshi.net` so the gemspec email matches. Verify the email.
2. **Enable MFA immediately**: Settings → *Multifactor Authentication* →
   register an authenticator app → set level to **"UI and API"** (the
   strongest; every push then needs an OTP, which is what you want for
   names you're holding in trust).
3. **Sign in the gem CLI**:

   ```sh
   gem signin        # prompts for email, password, OTP; stores a scoped key
   ```

   When prompted for API key scopes, `push_rubygem` alone is sufficient.

## Publishing

```sh
ruby generate.rb    # builds the 8 gems into pkg/
./push.sh           # re-checks availability, pushes (8 OTP prompts), verifies
```

`push.sh` aborts before pushing anything if any name has been taken since the
last availability check.

## Afterwards

- Update the RFC's *Gem name governance* date ("names registered <date>").
- The first push of each gem makes this account its owner. When AWS engages:
  `gem owner --add <aws-email> <name>` then optionally
  `gem owner --remove <your-email> <name>`.
- Real releases simply supersede the placeholders — nothing to yank. (Yanking
  the placeholder would *release* the name; don't.)
