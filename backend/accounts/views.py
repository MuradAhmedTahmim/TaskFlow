from django.contrib.auth import get_user_model
from django.db.models import Q
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView

from .serializers import (
    ChangePasswordSerializer,
    LoginSerializer,
    RegisterSerializer,
    UserProfileSerializer,
    UserSummarySerializer,
)

User = get_user_model()


def tokens_for(user):
    refresh = RefreshToken.for_user(user)
    return {"refresh": str(refresh), "access": str(refresh.access_token)}


class RegisterView(generics.CreateAPIView):
    serializer_class = RegisterSerializer
    permission_classes = [permissions.AllowAny]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(
            {**tokens_for(user), "user": UserProfileSerializer(user).data},
            status=status.HTTP_201_CREATED,
        )


class LoginView(TokenObtainPairView):
    serializer_class = LoginSerializer


class LogoutView(APIView):
    """Blacklists the given refresh token so it can no longer be used."""

    def post(self, request):
        token = request.data.get("refresh")
        if not token:
            return Response({"refresh": ["This field is required."]}, status=status.HTTP_400_BAD_REQUEST)
        try:
            RefreshToken(token).blacklist()
        except TokenError:
            return Response({"detail": "Invalid or expired token."}, status=status.HTTP_400_BAD_REQUEST)
        return Response(status=status.HTTP_205_RESET_CONTENT)


class MeView(generics.RetrieveUpdateDestroyAPIView):
    """View, update or delete the signed-in user's own account.

    DELETE needs the current password in the body ({"password": "..."}).
    Projects the user owns are deleted with their tasks; in other projects the
    user's tasks become unassigned (see the model on_delete rules).
    """

    serializer_class = UserProfileSerializer

    def get_object(self):
        return self.request.user

    def destroy(self, request, *args, **kwargs):
        password = request.data.get("password") or ""
        if not password:
            return Response({"password": ["Enter your password to confirm."]}, status=status.HTTP_400_BAD_REQUEST)
        if not request.user.check_password(password):
            return Response({"password": ["Password is incorrect."]}, status=status.HTTP_400_BAD_REQUEST)
        request.user.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class ChangePasswordView(APIView):
    def post(self, request):
        serializer = ChangePasswordSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        request.user.set_password(serializer.validated_data["new_password"])
        request.user.save(update_fields=["password"])
        return Response({"detail": "Password updated."})


class UserLookupView(generics.ListAPIView):
    """Search users by username, name or email (used for adding project members)."""

    serializer_class = UserSummarySerializer

    def get_queryset(self):
        query = self.request.query_params.get("search", "").strip()
        if len(query) < 2:
            return User.objects.none()
        return (
            User.objects.filter(is_active=True)
            .filter(Q(username__icontains=query) | Q(full_name__icontains=query) | Q(email__icontains=query))
            .order_by("username")[:20]
        )

    def list(self, request, *args, **kwargs):
        return Response(self.get_serializer(self.get_queryset(), many=True).data)
