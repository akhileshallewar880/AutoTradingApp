class UserModel {
  final String accessToken;
  final String apiKey;
  final String userId;
  final String userName;
  final String email;
  final String userType;
  final String broker;
  final List<String> exchanges;
  final List<String> products;
  // Phone auth additions — optional, backward-compatible with stored sessions
  final String? phoneNumber;
  final String? vtAccessToken;

  UserModel({
    required this.accessToken,
    required this.apiKey,
    required this.userId,
    required this.userName,
    required this.email,
    required this.userType,
    required this.broker,
    required this.exchanges,
    required this.products,
    this.phoneNumber,
    this.vtAccessToken,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      accessToken: json['access_token'] as String? ?? '',
      apiKey: json['api_key'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      userName: json['user_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      userType: json['user_type'] as String? ?? 'individual',
      broker: json['broker'] as String? ?? '',
      exchanges: List<String>.from((json['exchanges'] as List?) ?? []),
      products: List<String>.from((json['products'] as List?) ?? []),
      phoneNumber: json['phone_number'] as String?,
      vtAccessToken: json['vt_access_token'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'api_key': apiKey,
      'user_id': userId,
      'user_name': userName,
      'email': email,
      'user_type': userType,
      'broker': broker,
      'exchanges': exchanges,
      'products': products,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (vtAccessToken != null) 'vt_access_token': vtAccessToken,
    };
  }
}
