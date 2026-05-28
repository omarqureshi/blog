import React, { useState, useEffect } from 'react';
import { CognitoUserPool, AuthenticationDetails, CognitoUser } from 'amazon-cognito-identity-js';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';
import './AdminDashboard.css';

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
      <div className="admin-login-container">
        <h2>Admin Login</h2>
        {error && <p className="admin-error">{error}</p>}
        {requireNewPassword ? (
          <form onSubmit={handleNewPassword} className="admin-form">
            <p>You must change your temporary password.</p>
            <input type="password" placeholder="New Password" value={newPassword} onChange={e => setNewPassword(e.target.value)} required className="admin-input" />
            <button type="submit" className="admin-button">Set Password</button>
          </form>
        ) : (
          <form onSubmit={handleLogin} className="admin-form">
            <input type="email" placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} required className="admin-input" />
            <input type="password" placeholder="Password" value={password} onChange={e => setPassword(e.target.value)} required className="admin-input" />
            <button type="submit" className="admin-button">Login</button>
          </form>
        )}
      </div>
    );
  }

  return (
    <div className="admin-dashboard-container">
      <div className="admin-header">
        <h1>Analytics Dashboard</h1>
        <button onClick={handleLogout} className="admin-button-secondary">Logout</button>
      </div>

      {loading && <p>Loading real-time analytics...</p>}
      {error && <p className="admin-error">{error}</p>}
      
      {data && (
        <div>
          <div className="admin-metrics-row">
            <div className="admin-card">
              <h3>Total Pageviews</h3>
              <p>{data.total_views}</p>
            </div>
            <div className="admin-card">
              <h3>Unique Visitors (7d)</h3>
              <p>{data.unique_visitors}</p>
            </div>
          </div>

          <div className="admin-chart-container">
            <h3>Top Pages</h3>
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={data.top_pages} layout="vertical" margin={{ left: 50 }}>
                <XAxis type="number" />
                <YAxis dataKey="path" type="category" width={100} />
                <Tooltip />
                <Bar dataKey="views" fill="#8884d8" />
              </BarChart>
            </ResponsiveContainer>
          </div>

          <div className="admin-lists-row">
            <div className="admin-list-col">
              <h3>Top Referrers</h3>
              <ul className="admin-list">
                {data.top_referrers.map((r, i) => (
                  <li key={i}>{r.referrer} ({r.views} views)</li>
                ))}
              </ul>
            </div>
            <div className="admin-list-col">
              <h3>Top Countries</h3>
              <ul className="admin-list">
                {data.top_countries.map((c, i) => (
                  <li key={i}>{c.country} ({c.views} views)</li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
