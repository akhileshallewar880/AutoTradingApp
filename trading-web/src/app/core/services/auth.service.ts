import { Injectable, signal, computed } from '@angular/core';
import { User } from '../models';

const STORAGE_KEY = 'vantrade_user';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private _user = signal<User | null>(this._loadUser());

  readonly user    = this._user.asReadonly();
  readonly isLoggedIn = computed(() => !!this._user());

  login(user: User): void {
    this._user.set(user);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(user));
  }

  logout(): void {
    this._user.set(null);
    localStorage.removeItem(STORAGE_KEY);
  }

  private _loadUser(): User | null {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch { return null; }
  }
}
