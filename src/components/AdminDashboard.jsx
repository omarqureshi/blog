import React, { useState, useEffect } from 'react';
import { CognitoUserPool, AuthenticationDetails, CognitoUser } from 'amazon-cognito-identity-js';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';

export default function AdminDashboard() {
  const [session, setSession] = useState(null);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [cognitoUser, setCognitoUser] = useState(null);
  const [requireNewPassword, setRequireNewPassword] = useState(false);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // Configuration - Ensure you replace these with your actual output values after deployment
  const poolData = {
    UserPoolId: import.meta.env.PUBLIC_USER_POOL_ID || 'UPDATE_ME',
    ClientId: import.meta.env.PUBLIC_CLIENT_ID || 'UPDATE_ME'
  };
  
  const API_ENDPOINT = import.meta.env.PUBLIC_API_ENDPOINT || 'UPDATE_ME';

  useEffect(() => {
    // Check if user is already logged in
    if (poolData.UserPoolId !== 'UPDATE_ME') {
      const userPool = new CognitoUserPool(poolData);
      const user = userPool.getCurrentUser();
      if (user) {
        user.getSession((err, session) => {
          if (err) {
            console.error(err);
            return;
          }
          if (session.isValid()) {
            setSession(session);
            fetchData(session.getIdToken().getJwtToken());
          }
        });
      }
    }
  }, []);

  const handleLogin = (e) => {
    e.preventDefault();
    setError('');
    
    if (poolData.UserPoolId === 'UPDATE_ME') {
      setError('Please update the UserPoolId and ClientId in AdminDashboard.jsx first!');
      return;
    }

    const userPool = new CognitoUserPool(poolData);
    const authenticationDetails = new AuthenticationDetails({
      Username: email,
      Password: password,
    });

    const user = new CognitoUser({
      Username: email,
      Pool: userPool
    });

    user.authenticateUser(authenticationDetails, {
      onSuccess: (session) => {
        setSession(session);
        fetchData(session.getIdToken().getJwtToken());
      },
      onFailure: (err) => {
        setError(err.message || JSON.stringify(err));
      },
      newPasswordRequired: (userAttributes, requiredAttributes) => {
        // When admin creates a user, it requires a new password on first login
        setRequireNewPassword(true);
        setCognitoUser(user);
      }
    });
  };

  const handleNewPassword = (e) => {
    e.preventDefault();
    cognitoUser.completeNewPasswordChallenge(newPassword, {}, {
      onSuccess: (session) => {
        setRequireNewPassword(false);
        setSession(session);
        fetchData(session.getIdToken().getJwtToken());
      },
      onFailure: (err) => {
        setError(err.message || JSON.stringify(err));
      }
    });
  };

  const fetchData = async (token) => {
    setLoading(true);
    try {
      const response = await fetch(`${API_ENDPOINT}/analytics`, {
        headers: {
          'Authorization': token
        }
      });
      if (!response.ok) throw new Error('API Request Failed');
      const json = await response.json();
      setData(json);
    } catch (err) {
      setError(err.message);
    }
    setLoading(false);
  };

  const handleLogout = () => {
    const userPool = new CognitoUserPool(poolData);
    const user = userPool.getCurrentUser();
    if (user) user.signOut();
    setSession(null);
    setData(null);
  };

  if (!session) {
    return (
      <div style={{ maxWidth: '400px', margin: '100px auto', fontFamily: 'sans-serif' }}>
        <h2>Admin Login</h2>
        {error && <p style={{ color: 'red' }}>{error}</p>}
        {requireNewPassword ? (
          <form onSubmit={handleNewPassword} style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
            <p>You must change your temporary password.</p>
            <input type="password" placeholder="New Password" value={newPassword} onChange={e => setNewPassword(e.target.value)} required />
            <button type="submit" style={{ padding: '10px', background: '#333', color: '#fff' }}>Set Password</button>
          </form>
        ) : (
          <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
            <input type="email" placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} required />
            <input type="password" placeholder="Password" value={password} onChange={e => setPassword(e.target.value)} required />
            <button type="submit" style={{ padding: '10px', background: '#333', color: '#fff' }}>Login</button>
          </form>
        )}
      </div>
    );
  }

  return (
    <div style={{ padding: '40px', fontFamily: 'sans-serif', maxWidth: '800px', margin: '0 auto' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h1>Analytics Dashboard</h1>
        <button onClick={handleLogout} style={{ padding: '5px 10px' }}>Logout</button>
      </div>

      {loading && <p>Loading data from Athena...</p>}
      {error && <p style={{ color: 'red' }}>{error}</p>}
      
      {data && data.length > 0 && (
        <div style={{ height: '400px', marginTop: '40px' }}>
          <h3>Top Visited Pages</h3>
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={data}>
              <XAxis dataKey="path" />
              <YAxis />
              <Tooltip />
              <Bar dataKey="views" fill="#8884d8" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}
      {data && data.length === 0 && <p>No data found in the logs yet.</p>}
    </div>
  );
}
