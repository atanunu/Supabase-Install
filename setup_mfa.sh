#!/bin/bash

# 🔐 Multi-Factor Authentication (MFA) Setup for Supabase
# Configures TOTP-based MFA using authenticator apps

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MFA_CONFIG_DIR="${SCRIPT_DIR}/mfa_config"
LOG_FILE="${SCRIPT_DIR}/mfa_setup.log"

# Logging functions
log() {
    echo -e "${2:-$NC}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1" "$RED"
    exit 1
}

success() {
    log "SUCCESS: $1" "$GREEN"
}

warn() {
    log "WARNING: $1" "$YELLOW"
}

info() {
    log "INFO: $1" "$BLUE"
}

# Create MFA configuration directory
create_mfa_directories() {
    info "Creating MFA configuration directories..."
    
    mkdir -p "$MFA_CONFIG_DIR"
    mkdir -p "${MFA_CONFIG_DIR}/migrations"
    mkdir -p "${MFA_CONFIG_DIR}/functions"
    
    chmod 755 "$MFA_CONFIG_DIR"
    
    success "MFA directories created"
}

# Generate MFA database schema
create_mfa_schema() {
    info "Creating MFA database schema..."
    
    cat > "${MFA_CONFIG_DIR}/migrations/001_create_mfa_tables.sql" << 'EOF'
-- MFA Tables for Supabase Auth Enhancement
-- Run this migration in your Supabase database

-- Create MFA factors table
CREATE TABLE IF NOT EXISTS auth.mfa_factors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    friendly_name TEXT,
    factor_type TEXT NOT NULL CHECK (factor_type IN ('totp', 'phone')),
    status TEXT NOT NULL DEFAULT 'unverified' CHECK (status IN ('unverified', 'verified')),
    secret TEXT NOT NULL,
    phone TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT unique_user_factor_name UNIQUE (user_id, friendly_name)
);

-- Create MFA challenges table
CREATE TABLE IF NOT EXISTS auth.mfa_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    factor_id UUID NOT NULL REFERENCES auth.mfa_factors(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    verified_at TIMESTAMPTZ,
    ip_address INET,
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '5 minutes'),
    
    CONSTRAINT challenges_not_expired CHECK (expires_at > created_at)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_mfa_factors_user_id ON auth.mfa_factors(user_id);
CREATE INDEX IF NOT EXISTS idx_mfa_factors_status ON auth.mfa_factors(status);
CREATE INDEX IF NOT EXISTS idx_mfa_challenges_factor_id ON auth.mfa_challenges(factor_id);
CREATE INDEX IF NOT EXISTS idx_mfa_challenges_expires_at ON auth.mfa_challenges(expires_at);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION auth.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS update_mfa_factors_updated_at ON auth.mfa_factors;
CREATE TRIGGER update_mfa_factors_updated_at
    BEFORE UPDATE ON auth.mfa_factors
    FOR EACH ROW
    EXECUTE FUNCTION auth.update_updated_at_column();

-- Create RLS policies
ALTER TABLE auth.mfa_factors ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.mfa_challenges ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only access their own MFA factors
CREATE POLICY "Users can manage their own MFA factors" ON auth.mfa_factors
    FOR ALL USING (auth.uid() = user_id);

-- Policy: Users can only access their own MFA challenges
CREATE POLICY "Users can manage their own MFA challenges" ON auth.mfa_challenges
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM auth.mfa_factors
            WHERE id = factor_id AND user_id = auth.uid()
        )
    );

-- Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.mfa_factors TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.mfa_challenges TO authenticated;

-- Create cleanup function for expired challenges
CREATE OR REPLACE FUNCTION auth.cleanup_expired_mfa_challenges()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM auth.mfa_challenges
    WHERE expires_at < NOW();
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to generate TOTP secret
CREATE OR REPLACE FUNCTION auth.generate_totp_secret()
RETURNS TEXT AS $$
BEGIN
    -- Generate 32-character base32 secret
    RETURN upper(encode(gen_random_bytes(20), 'base32'));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON TABLE auth.mfa_factors IS 'Multi-factor authentication factors for users';
COMMENT ON TABLE auth.mfa_challenges IS 'MFA challenges for verification';
EOF

    success "MFA database schema created"
}

# Create MFA edge functions
create_mfa_functions() {
    info "Creating MFA Edge Functions..."
    
    # TOTP Setup Function
    cat > "${MFA_CONFIG_DIR}/functions/setup-totp.js" << 'EOF'
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const authHeader = req.headers.get('Authorization')!
    const token = authHeader.replace('Bearer ', '')
    
    const { data: { user } } = await supabase.auth.getUser(token)
    if (!user) {
      throw new Error('Unauthorized')
    }

    const { friendly_name } = await req.json()

    // Generate TOTP secret
    const { data: secretData } = await supabase.rpc('generate_totp_secret')
    const secret = secretData

    // Insert MFA factor
    const { data: factor, error } = await supabase
      .from('mfa_factors')
      .insert({
        user_id: user.id,
        friendly_name: friendly_name || 'Authenticator App',
        factor_type: 'totp',
        secret: secret,
        status: 'unverified'
      })
      .select()
      .single()

    if (error) {
      throw error
    }

    // Generate QR code data
    const appName = Deno.env.get('SITE_URL') || 'Supabase App'
    const qrData = `otpauth://totp/${encodeURIComponent(appName)}:${encodeURIComponent(user.email)}?secret=${secret}&issuer=${encodeURIComponent(appName)}`

    return new Response(
      JSON.stringify({
        factor_id: factor.id,
        secret: secret,
        qr_code: qrData,
        backup_codes: [] // TODO: Generate backup codes
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      },
    )
  }
})
EOF

    # TOTP Verification Function
    cat > "${MFA_CONFIG_DIR}/functions/verify-totp.js" << 'EOF'
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { authenticator } from 'https://esm.sh/otplib@12.0.1'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const authHeader = req.headers.get('Authorization')!
    const token = authHeader.replace('Bearer ', '')
    
    const { data: { user } } = await supabase.auth.getUser(token)
    if (!user) {
      throw new Error('Unauthorized')
    }

    const { factor_id, code } = await req.json()

    // Get the MFA factor
    const { data: factor, error: factorError } = await supabase
      .from('mfa_factors')
      .select('*')
      .eq('id', factor_id)
      .eq('user_id', user.id)
      .single()

    if (factorError || !factor) {
      throw new Error('MFA factor not found')
    }

    // Verify TOTP code
    const isValid = authenticator.verify({
      token: code,
      secret: factor.secret
    })

    if (!isValid) {
      throw new Error('Invalid verification code')
    }

    // Update factor status to verified
    const { error: updateError } = await supabase
      .from('mfa_factors')
      .update({ status: 'verified' })
      .eq('id', factor_id)

    if (updateError) {
      throw updateError
    }

    // Create challenge record
    const { data: challenge } = await supabase
      .from('mfa_challenges')
      .insert({
        factor_id: factor_id,
        verified_at: new Date().toISOString(),
        ip_address: req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for')
      })
      .select()
      .single()

    return new Response(
      JSON.stringify({
        success: true,
        challenge_id: challenge?.id
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      },
    )
  }
})
EOF

    # MFA Status Function
    cat > "${MFA_CONFIG_DIR}/functions/mfa-status.js" << 'EOF'
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const authHeader = req.headers.get('Authorization')!
    const token = authHeader.replace('Bearer ', '')
    
    const { data: { user } } = await supabase.auth.getUser(token)
    if (!user) {
      throw new Error('Unauthorized')
    }

    // Get user's MFA factors
    const { data: factors, error } = await supabase
      .from('mfa_factors')
      .select('id, friendly_name, factor_type, status, created_at')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })

    if (error) {
      throw error
    }

    const hasMFA = factors && factors.length > 0
    const hasVerifiedMFA = factors && factors.some(f => f.status === 'verified')

    return new Response(
      JSON.stringify({
        mfa_enabled: hasMFA,
        mfa_verified: hasVerifiedMFA,
        factors: factors || []
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      },
    )
  }
})
EOF

    success "MFA Edge Functions created"
}

# Create MFA frontend components
create_mfa_frontend() {
    info "Creating MFA frontend components..."
    
    cat > "${MFA_CONFIG_DIR}/mfa-setup.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Setup Two-Factor Authentication</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background: white;
            border-radius: 8px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .step {
            margin-bottom: 30px;
            padding: 20px;
            border: 1px solid #e0e0e0;
            border-radius: 6px;
        }
        .step h3 {
            margin-top: 0;
            color: #333;
        }
        .qr-code {
            text-align: center;
            margin: 20px 0;
        }
        .secret-code {
            background: #f8f9fa;
            padding: 10px;
            border-radius: 4px;
            font-family: monospace;
            word-break: break-all;
            margin: 10px 0;
        }
        .input-group {
            margin: 15px 0;
        }
        .input-group label {
            display: block;
            margin-bottom: 5px;
            font-weight: 500;
        }
        .input-group input {
            width: 100%;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 16px;
        }
        .btn {
            background: #0066cc;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 16px;
        }
        .btn:hover {
            background: #0052a3;
        }
        .btn:disabled {
            background: #ccc;
            cursor: not-allowed;
        }
        .success {
            background: #d4edda;
            color: #155724;
            padding: 10px;
            border-radius: 4px;
            margin: 10px 0;
        }
        .error {
            background: #f8d7da;
            color: #721c24;
            padding: 10px;
            border-radius: 4px;
            margin: 10px 0;
        }
        .hidden {
            display: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Setup Two-Factor Authentication</h1>
        
        <div id="step1" class="step">
            <h3>Step 1: Install Authenticator App</h3>
            <p>Download and install an authenticator app on your phone:</p>
            <ul>
                <li><strong>Google Authenticator</strong> (iOS/Android)</li>
                <li><strong>Authy</strong> (iOS/Android/Desktop)</li>
                <li><strong>Microsoft Authenticator</strong> (iOS/Android)</li>
                <li><strong>1Password</strong> (Premium feature)</li>
            </ul>
        </div>

        <div id="step2" class="step">
            <h3>Step 2: Scan QR Code</h3>
            <div class="input-group">
                <label for="deviceName">Device Name (optional):</label>
                <input type="text" id="deviceName" placeholder="My Phone" />
            </div>
            <button class="btn" onclick="setupMFA()">Generate QR Code</button>
            
            <div id="qrSection" class="hidden">
                <div class="qr-code">
                    <div id="qrcode"></div>
                </div>
                <p>Can't scan the QR code? Enter this secret manually:</p>
                <div class="secret-code" id="secretCode"></div>
            </div>
        </div>

        <div id="step3" class="step hidden">
            <h3>Step 3: Verify Setup</h3>
            <p>Enter the 6-digit code from your authenticator app:</p>
            <div class="input-group">
                <label for="verificationCode">Verification Code:</label>
                <input type="text" id="verificationCode" placeholder="123456" maxlength="6" />
            </div>
            <button class="btn" onclick="verifyMFA()">Verify & Enable MFA</button>
        </div>

        <div id="messages"></div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/qrcode@1.5.3/build/qrcode.min.js"></script>
    <script>
        let currentFactorId = null;

        function showMessage(message, type = 'success') {
            const messagesDiv = document.getElementById('messages');
            messagesDiv.innerHTML = `<div class="${type}">${message}</div>`;
            setTimeout(() => {
                messagesDiv.innerHTML = '';
            }, 5000);
        }

        async function setupMFA() {
            try {
                const deviceName = document.getElementById('deviceName').value || 'Authenticator App';
                
                const response = await fetch('/functions/v1/setup-totp', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${getToken()}`
                    },
                    body: JSON.stringify({ friendly_name: deviceName })
                });

                const data = await response.json();
                
                if (!response.ok) {
                    throw new Error(data.error);
                }

                currentFactorId = data.factor_id;
                
                // Generate QR code
                const qrCodeElement = document.getElementById('qrcode');
                qrCodeElement.innerHTML = '';
                QRCode.toCanvas(qrCodeElement, data.qr_code, function (error) {
                    if (error) console.error(error);
                });

                // Show secret code
                document.getElementById('secretCode').textContent = data.secret;
                
                // Show QR section and step 3
                document.getElementById('qrSection').classList.remove('hidden');
                document.getElementById('step3').classList.remove('hidden');
                
                showMessage('QR code generated! Scan it with your authenticator app.');
                
            } catch (error) {
                showMessage(error.message, 'error');
            }
        }

        async function verifyMFA() {
            try {
                const code = document.getElementById('verificationCode').value;
                
                if (!code || code.length !== 6) {
                    throw new Error('Please enter a 6-digit verification code');
                }

                const response = await fetch('/functions/v1/verify-totp', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${getToken()}`
                    },
                    body: JSON.stringify({ 
                        factor_id: currentFactorId,
                        code: code 
                    })
                });

                const data = await response.json();
                
                if (!response.ok) {
                    throw new Error(data.error);
                }

                showMessage('🎉 Two-factor authentication has been successfully enabled!');
                
                // Hide verification form
                document.getElementById('step3').style.display = 'none';
                
                setTimeout(() => {
                    window.location.href = '/dashboard';
                }, 2000);
                
            } catch (error) {
                showMessage(error.message, 'error');
            }
        }

        function getToken() {
            // This should return the user's JWT token
            // Implementation depends on your auth setup
            return localStorage.getItem('supabase.auth.token') || '';
        }
    </script>
</body>
</html>
EOF

    success "MFA frontend components created"
}

# Create deployment script
create_deployment_script() {
    info "Creating MFA deployment script..."
    
    cat > "${MFA_CONFIG_DIR}/deploy_mfa.sh" << 'EOF'
#!/bin/bash

# Deploy MFA to Supabase
set -euo pipefail

echo "🔐 Deploying MFA to Supabase..."

# Check if Supabase CLI is installed
if ! command -v supabase >/dev/null 2>&1; then
    echo "Installing Supabase CLI..."
    npm install -g supabase
fi

# Apply database migrations
echo "Applying database migrations..."
supabase db push

# Deploy edge functions
echo "Deploying Edge Functions..."
supabase functions deploy setup-totp --project-ref YOUR_PROJECT_REF
supabase functions deploy verify-totp --project-ref YOUR_PROJECT_REF
supabase functions deploy mfa-status --project-ref YOUR_PROJECT_REF

echo "✅ MFA deployment complete!"
echo
echo "Next steps:"
echo "1. Update your project reference in this script"
echo "2. Configure environment variables in Supabase dashboard"
echo "3. Test MFA setup with the provided HTML interface"
EOF

    chmod +x "${MFA_CONFIG_DIR}/deploy_mfa.sh"
    
    success "MFA deployment script created"
}

# Create MFA configuration guide
create_mfa_guide() {
    info "Creating MFA setup guide..."
    
    cat > "${MFA_CONFIG_DIR}/README.md" << 'EOF'
# Multi-Factor Authentication (MFA) Setup Guide

This directory contains everything needed to add TOTP-based MFA to your Supabase application.

## Files Overview

- `migrations/001_create_mfa_tables.sql` - Database schema for MFA
- `functions/` - Edge Functions for MFA operations
- `mfa-setup.html` - Frontend interface for MFA setup
- `deploy_mfa.sh` - Deployment script
- `README.md` - This guide

## Quick Setup

1. **Apply Database Migration**
   ```sql
   -- Run in your Supabase SQL editor
   -- Copy and paste content from migrations/001_create_mfa_tables.sql
   ```

2. **Deploy Edge Functions**
   ```bash
   # Install Supabase CLI if not already installed
   npm install -g supabase

   # Deploy functions
   supabase functions deploy setup-totp
   supabase functions deploy verify-totp
   supabase functions deploy mfa-status
   ```

3. **Environment Variables**
   Add these to your Supabase project settings:
   ```
   SUPABASE_URL=your_supabase_url
   SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
   SITE_URL=your_site_url
   ```

4. **Frontend Integration**
   - Host `mfa-setup.html` or integrate the components into your app
   - Update the `getToken()` function to return the user's JWT

## API Endpoints

### Setup TOTP
```javascript
POST /functions/v1/setup-totp
Headers: Authorization: Bearer <jwt_token>
Body: { "friendly_name": "My Phone" }
```

### Verify TOTP
```javascript
POST /functions/v1/verify-totp
Headers: Authorization: Bearer <jwt_token>
Body: { "factor_id": "uuid", "code": "123456" }
```

### Check MFA Status
```javascript
GET /functions/v1/mfa-status
Headers: Authorization: Bearer <jwt_token>
```

## Integration Example

```javascript
// Check if user has MFA enabled
const checkMFAStatus = async () => {
  const { data } = await supabase.functions.invoke('mfa-status', {
    headers: { Authorization: `Bearer ${session.access_token}` }
  });
  return data;
};

// Setup MFA for user
const setupMFA = async (deviceName) => {
  const { data } = await supabase.functions.invoke('setup-totp', {
    body: { friendly_name: deviceName },
    headers: { Authorization: `Bearer ${session.access_token}` }
  });
  return data;
};

// Verify MFA code
const verifyMFA = async (factorId, code) => {
  const { data } = await supabase.functions.invoke('verify-totp', {
    body: { factor_id: factorId, code },
    headers: { Authorization: `Bearer ${session.access_token}` }
  });
  return data;
};
```

## Security Considerations

1. **Backup Codes**: Implement backup codes for account recovery
2. **Rate Limiting**: Add rate limiting to verification endpoints
3. **Audit Logging**: Log all MFA operations for security monitoring
4. **Token Validation**: Ensure proper JWT validation in edge functions

## Testing

1. Create a test user account
2. Navigate to the MFA setup page
3. Follow the setup process with an authenticator app
4. Test verification with generated codes
5. Verify database entries are created correctly

## Troubleshooting

### Common Issues

1. **"Unauthorized" errors**: Check JWT token validity
2. **QR code not displaying**: Verify QR code library is loaded
3. **Invalid verification code**: Check device time synchronization
4. **Function deployment fails**: Verify Supabase CLI authentication

### Database Queries

```sql
-- Check MFA factors for a user
SELECT * FROM auth.mfa_factors WHERE user_id = 'user_uuid';

-- Check MFA challenges
SELECT * FROM auth.mfa_challenges WHERE factor_id = 'factor_uuid';

-- Clean up expired challenges
SELECT auth.cleanup_expired_mfa_challenges();
```

## Next Steps

1. Implement backup codes
2. Add SMS-based MFA option
3. Create admin interface for MFA management
4. Add MFA requirement policies
5. Implement remember device functionality
EOF

    success "MFA setup guide created"
}

# Main function
main() {
    log "🔐 Starting MFA Setup for Supabase" "$BLUE"
    
    # Create directory structure
    create_mfa_directories
    
    # Generate MFA components
    create_mfa_schema
    create_mfa_functions
    create_mfa_frontend
    create_deployment_script
    create_mfa_guide
    
    echo
    success "🔐 MFA setup complete!"
    echo
    echo "📁 MFA files created in: $MFA_CONFIG_DIR"
    echo
    echo "📋 Next steps:"
    echo "1. Apply database migration: Copy SQL from migrations/001_create_mfa_tables.sql"
    echo "2. Deploy Edge Functions: cd $MFA_CONFIG_DIR && ./deploy_mfa.sh"
    echo "3. Configure environment variables in Supabase dashboard"
    echo "4. Test MFA setup with mfa-setup.html"
    echo
    echo "📖 Full guide: $MFA_CONFIG_DIR/README.md"
}

# Run main function
main "$@"
